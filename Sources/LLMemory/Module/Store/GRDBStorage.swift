//
//  GRDBStorage.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
import Storage

// How this one database is put together and opened. Nothing about the brain
// around it is here — no lock, no cache, no announcement; that is `BrainStore`,
// which owns one of these and is the only thing that holds it.
public final class GRDBStorage: DBDriver, DBStorable, @unchecked Sendable {
    // MARK: - Property
    private let databaseURL: URL
    private let migrations: [any GRDBMigration]

    private let stateLock = NSLock()
    private var cached: DatabaseQueue?

    private var brainRootPath: String {
        databaseURL.deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    // MARK: - Initializer
    public init(databaseURL: URL, migrations: [any GRDBMigration]) {
        self.databaseURL = databaseURL
        self.migrations = migrations
    }

    // MARK: - Lifecycle
    public func connect() throws -> any DatabaseWriter {
        stateLock.lock()

        defer { stateLock.unlock() }

        if let cached {
            return cached
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

        cached = connection

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

        cached = nil
    }

    public func reset() throws {
        stateLock.lock()

        defer { stateLock.unlock() }

        cached = nil

        let fileManager = FileManager.default

        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: databaseURL.path + suffix)

            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - Public
    // Nothing to do ahead of time: `connect` opens the file, checks the
    // migration state and caches the result on first use, so a store is as
    // ready as this database gets the moment it exists. What it is *not* is
    // migrated — carrying a brain's schema forward is `migrateSchema`, and it
    // happens only where a caller asked for it, so a stale brain refuses at
    // `open` instead of being moved by whoever opened it first.
    public func initialize() throws { }

    // Create the file if it is missing, migrate it, then cache. The order is
    // this database's answer: `connect` refuses while migrations are pending,
    // which is the very state this exists to leave.
    public func migrateSchema() throws {
        let dataDirectory = databaseURL.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: dataDirectory.path) else {
            throw DBError.dataDirMissing(dataDirectory.path)
        }

        stateLock.lock()

        let connection: DatabaseQueue
        let wasCached: Bool

        do {
            if let opened = cached {
                connection = opened
                wasCached = true
            } else {
                connection = try DatabaseQueue(
                    path: databaseURL.path,
                    configuration: Self.makeConfiguration()
                )
                wasCached = false
            }

            stateLock.unlock()
        } catch {
            stateLock.unlock()
            throw error
        }

        try migrate(connection: connection)

        // Cache only a validated connection — caching before the migration/shape
        // gate would let later connects hand out an unverified one.
        if !wasCached {
            stateLock.lock()
            cached = connection
            stateLock.unlock()
        }
    }

    // A read gets a read connection, which is what `readOnly` was passed here
    // to buy. Whatever wider exclusion the caller needs is the caller's — this
    // opens a transaction and nothing else.
    public func open<T>(
        readOnly: Bool,
        _ body: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        let connection = try connect()

        return readOnly
            ? try await connection.read { db in try body(db) }
            : try await connection.write { db in try body(db) }
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
}
