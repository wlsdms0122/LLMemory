//
//  GRDBStorage.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
import Storage

@_silgen_name("flock") private func c_flock(_ fd: Int32, _ op: Int32) -> Int32

public protocol GRDBStorable: DBStorable where Connection == any DatabaseWriter { }

public final class GRDBStorage: GRDBStorable, @unchecked Sendable {
    // MARK: - Property
    private let databaseURL: URL
    private let migrations: [any GRDBMigration]

    private let stateLock = NSLock()
    private var connection: DatabaseQueue?

    // flock(2) — cross-process write exclusion between concurrent CLI invocations.
    // In-process nesting is tracked by lockDepth under writeSection.
    private var lockDescriptor: Int32 = -1
    private var lockDepth: Int = 0
    private let lockMutex = NSLock()
    private let writeSection = NSRecursiveLock()

    private var brainRootPath: String {
        databaseURL.deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    // MARK: - Initializer
    public init(
        databaseURL: URL,
        migrations: [any GRDBMigration]
    ) {
        self.databaseURL = databaseURL
        self.migrations = migrations
    }

    // MARK: - Lifecycle
    public func connect() throws -> any DatabaseWriter {
        stateLock.lock()

        defer { stateLock.unlock() }

        if let connection {
            return connection
        }

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw DBError.notInitialized(brainRootPath)
        }

        let connection = try DatabaseQueue(
            path: databaseURL.path,
            configuration: Self.makeConfiguration()
        )
        let migrator = makeMigrator()

        try connection.read { db in
            if try migrator.hasBeenSuperseded(db) {
                throw DBError.superseded(brainRoot: brainRootPath)
            }

            if try !migrator.hasCompletedMigrations(db) {
                throw DBError.pendingMigrations(brainRoot: brainRootPath)
            }
        }

        self.connection = connection

        return connection
    }

    public func migrate(connection: any DatabaseWriter) throws {
        try makeMigrator().migrate(connection)

        // IF NOT EXISTS DDL never alters an existing table, so a diverged legacy
        // shape survives the migration silently — surface it loudly here. The same
        // check runs continuously as verify L0 (`index verify`).
        let mismatches = try connection.read { db in
            try SchemaShape(migrations: migrations).check(db)
        }

        if !mismatches.isEmpty {
            throw DBError.schemaShapeMismatch(
                brainRoot: brainRootPath,
                mismatches: mismatches
            )
        }
    }

    // Drops the cached connection so the next access reopens the file — the
    // in-process equivalent of a fresh CLI invocation (tests, home rebinding).
    public func disconnect() {
        stateLock.lock()

        defer { stateLock.unlock() }

        connection = nil
    }

    public func reset() throws {
        stateLock.lock()

        defer { stateLock.unlock() }

        connection = nil

        let fileManager = FileManager.default

        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)

            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Public
    public func initialize() throws {
        let dataDirectory = databaseURL.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: dataDirectory.path) else {
            throw DBError.dataDirMissing(dataDirectory.path)
        }

        stateLock.lock()

        let connection: DatabaseQueue
        let cached: Bool

        do {
            if let opened = self.connection {
                connection = opened
                cached = true
            } else {
                connection = try DatabaseQueue(
                    path: databaseURL.path,
                    configuration: Self.makeConfiguration()
                )
                cached = false
            }

            stateLock.unlock()
        } catch {
            stateLock.unlock()
            throw error
        }

        try migrate(connection: connection)

        // Cache only a validated connection — caching before the migration/shape
        // gate would let later connects hand out an unverified one.
        if !cached {
            stateLock.lock()
            self.connection = connection
            stateLock.unlock()
        }
    }

    @discardableResult
    public func run<T: DBTransaction>(_ transaction: T) async throws -> T.Result where T.Connection == Connection {
        storage(self, willRun: transaction)

        do {
            let connection = try connect()
            let result: T.Result

            if transaction is any GRDBWriteTransaction {
                try acquireLock()

                do {
                    result = try await transaction.execute(connection)
                    releaseLock()
                } catch {
                    releaseLock()
                    throw error
                }
            } else {
                result = try await transaction.execute(connection)
            }

            storage(self, didRun: transaction, withResult: .success(result))

            return result
        } catch {
            storage(self, didRun: transaction, withResult: .failure(error))
            throw error
        }
    }

    // Interim direct-write surface for callers not yet converted to transactions.
    // Carries the same lock discipline as `run` for write transactions.
    public func writeLock<T>(_ body: () throws -> T) throws -> T {
        writeSection.lock()

        defer { writeSection.unlock() }

        try acquireLock()

        defer { releaseLock() }

        return try body()
    }

    @discardableResult
    public func write<T>(_ body: (Database) throws -> T) throws -> T {
        try writeLock {
            let connection = try connect()

            return try connection.write(body)
        }
    }

    // MARK: - Private
    private static func makeConfiguration() -> Configuration {
        var configuration = Configuration()
        configuration.busyMode = .timeout(10)
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        return configuration
    }

    private func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrations.sorted { lhs, rhs in lhs.id < rhs.id }
            .forEach { migration in
                migrator.registerMigration("\(migration.id)") { db in
                    try migration.migrate(db)
                }
            }

        return migrator
    }

    private func acquireLock() throws {
        lockMutex.lock()

        defer { lockMutex.unlock() }

        if lockDescriptor < 0 {
            let dataDirectory = databaseURL.deletingLastPathComponent()

            guard FileManager.default.fileExists(atPath: dataDirectory.path) else {
                throw DBError.dataDirMissing(dataDirectory.path)
            }

            let lockPath = dataDirectory.appendingPathComponent(".write.lock").path
            let descriptor = Darwin.open(lockPath, O_WRONLY | O_CREAT, 0o644)

            guard descriptor >= 0 else {
                throw DBError.lockFailed(errno: errno)
            }

            lockDescriptor = descriptor
        }

        if lockDepth == 0 {
            guard c_flock(lockDescriptor, LOCK_EX) == 0 else {
                throw DBError.lockFailed(errno: errno)
            }
        }

        lockDepth += 1
    }

    private func releaseLock() {
        lockMutex.lock()

        defer { lockMutex.unlock() }

        lockDepth -= 1

        if lockDepth == 0 && lockDescriptor >= 0 {
            _ = c_flock(lockDescriptor, LOCK_UN)
        }
    }

    deinit {
        if lockDescriptor >= 0 {
            _ = Darwin.close(lockDescriptor)
        }
    }
}
