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

public final class GRDBStorage: GRDBStorable, @unchecked Sendable {
    // MARK: - Property
    // The owning brain's ambient state — bound as a task-local around every
    // scope body, so Paths/Config/Genes resolve to this brain while its
    // transactions run (async GRDB closures leave the caller's task, so the
    // binding happens inside them, not just around the call).
    let context: BrainContext

    private let databaseURL: URL
    private let migrations: [any GRDBMigration]

    private let stateLock = NSLock()
    private var connection: DatabaseQueue?

    // flock(2) — cross-process write exclusion between concurrent CLI invocations.
    // The depth counter is only sound under exactly one in-process gate at a
    // time — writeSection (sync writeLock) or writeGate (async write
    // transactions) — so acquireLock records its owner and fails loud if the
    // other gate overlaps instead of silently skipping the flock.
    private enum LockOwner { case section, gate }

    private var lockDescriptor: Int32 = -1
    private var lockDepth: Int = 0
    private var lockOwner: LockOwner?
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
        migrations: [any GRDBMigration],
        context: BrainContext
    ) {
        self.databaseURL = databaseURL
        self.migrations = migrations
        self.context = context
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

    // The write scope — one flock + one BEGIN/COMMIT around the whole body.
    // Services orchestrate domain work inside; every DB touch goes through
    // scope.run(transaction). Throwing rolls the entire scope back.
    @discardableResult
    public func run<T: Sendable>(_ body: @escaping @Sendable (GRDBScope) throws -> T) async throws -> T {
        let connection = try connect()

        // In-process exclusion first — flock cannot separate two tasks of one
        // process (they share the descriptor, and the depth counter presumes an
        // outer mutex), so the async gate is what makes the counter sound here.
        // The flock wait and the scope body still block this thread — accepted
        // for the single-shot CLI; a dedicated queue is the recorded way out if
        // embedding ever needs it.
        await writeGate.acquire()

        defer { writeGate.release() }

        try acquireLock(as: .gate)

        defer { releaseLock() }

        // The process-global caches (config values, gene values) follow
        // committed state, and a write scope is where committed state changes.
        // Reloading here rather than inside the body is what makes that true on
        // both paths: a body that wrote and then threw rolls its rows back, and
        // the caches never held the rolled-back values to begin with.
        //
        // It runs while the gate and flock are still held — outside them
        // another writer's committed values could be clobbered by ours.
        defer { Config.reloadCommitted(self) }

        return try await connection.write { db in
            try self.context.bind { try body(GRDBScope(db)) }
        }
    }

    // The read scope — no lock, no write transaction; SQLite rejects writes
    // issued through it at runtime.
    @discardableResult
    public func read<T: Sendable>(_ body: @escaping @Sendable (GRDBReadScope) throws -> T) async throws -> T {
        try await connect().read { db in
            try self.context.bind { try body(GRDBReadScope(db)) }
        }
    }

    // The sync lifecycle gate — Session.bootstrap (which must run before the
    // migration gate can pass) and test fixtures. flock excludes it across
    // processes; in-process it never overlaps `run` writes because bootstrap
    // precedes any transaction dispatch.
    public func writeLock<T>(_ body: () throws -> T) throws -> T {
        writeSection.lock()

        defer { writeSection.unlock() }

        try acquireLock(as: .section)

        defer { releaseLock() }

        // The same reload as `run`: this is a write scope too, so the caches
        // follow what it committed.
        defer { Config.reloadCommitted(self) }

        return try context.bind(body)
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

    private func acquireLock(as owner: LockOwner) throws {
        lockMutex.lock()

        defer { lockMutex.unlock() }

        // Two gates never overlap by design (bootstrap precedes any transaction
        // dispatch); if that ever breaks, skipping the flock here would silently
        // drop cross-process exclusion — crash instead.
        precondition(
            lockDepth == 0 || lockOwner == owner,
            "write lock overlap across gates — writeSection and writeGate must never interleave"
        )

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

            lockOwner = owner
        }

        lockDepth += 1
    }

    private func releaseLock() {
        lockMutex.lock()

        defer { lockMutex.unlock() }

        lockDepth -= 1

        if lockDepth == 0 {
            lockOwner = nil

            if lockDescriptor >= 0 {
                _ = c_flock(lockDescriptor, LOCK_UN)
            }
        }
    }

    deinit {
        if lockDescriptor >= 0 {
            _ = Darwin.close(lockDescriptor)
        }
    }
}
