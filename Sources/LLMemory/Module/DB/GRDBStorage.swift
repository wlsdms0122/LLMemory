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
    // In-process nesting is tracked by lockDepth under writeSection (sync
    // writeLock) or writeGate (async write transactions).
    private var lockDescriptor: Int32 = -1
    private var lockDepth: Int = 0
    private let lockMutex = NSLock()
    private let writeSection = NSRecursiveLock()
    private let writeGate = WriteGate()

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
    public func run<T: GRDBWriteTransaction>(_ transaction: T) async throws -> T.Result {
        let connection = try connect()

        // In-process exclusion first — flock cannot separate two tasks of one
        // process (they share the descriptor, and the depth counter presumes an
        // outer mutex), so the async gate is what makes the counter sound here.
        await writeGate.acquire()

        defer { writeGate.release() }

        try acquireLock()

        defer { releaseLock() }

        return try await transaction.execute(connection)
    }

    @discardableResult
    public func run<T: GRDBTransaction>(_ transaction: T) async throws -> T.Result {
        try await transaction.execute(try connect())
    }

    // The sync lifecycle gate — Session.bootstrap (which must run before the
    // migration gate can pass) and test fixtures. flock excludes it across
    // processes; in-process it never overlaps `run` writes because bootstrap
    // precedes any transaction dispatch.
    public func writeLock<T>(_ body: () throws -> T) throws -> T {
        writeSection.lock()

        defer { writeSection.unlock() }

        try acquireLock()

        defer { releaseLock() }

        return try body()
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

// An async-safe mutex — waiters park as continuations instead of blocking a
// cooperative thread, and release may happen on any thread.
final class WriteGate: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initializer
    // MARK: - Public
    func acquire() async {
        await withCheckedContinuation { continuation in
            lock.lock()

            if busy {
                waiters.append(continuation)
                lock.unlock()
            } else {
                busy = true
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func release() {
        lock.lock()

        if waiters.isEmpty {
            busy = false
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }

    // MARK: - Private
}
