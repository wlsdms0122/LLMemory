//
//  BrainStore.swift
//  LLMemory
//
//  Created by JSilver on 8/18/26.
//

import Foundation
import GRDB
import Storage

// The store the rest of the package holds: a database, the fence around the
// brain it belongs to, and the announcement that committed state moved.
//
// The database knows nothing of the fence and the fence nothing of the
// database — one is a `DB` from the storage package, the other a file lock
// over this brain's directory. Putting them together is this type's whole job,
// and it is the reason no caller has to remember to take the second one.
public final class BrainStore: GRDBStorable {
    // MARK: - Property
    private let driver: GRDBStorage
    private let db: DB<Database>
    private let lock: BrainLock

    // What the owner of this store does once committed state has changed. The
    // store does not know what a brain is — it knows when the answer to "what
    // is committed" moved, and says so; whoever caches those answers decides
    // what that costs them.
    private let didCommit: @Sendable (any GRDBStorable) async -> Void

    // MARK: - Initializer
    private init(
        driver: GRDBStorage,
        db: DB<Database>,
        lock: BrainLock,
        didCommit: @escaping @Sendable (any GRDBStorable) async -> Void
    ) {
        self.driver = driver
        self.db = db
        self.lock = lock
        self.didCommit = didCommit
    }

    // MARK: - Public
    public static func open(
        _ driver: GRDBStorage,
        dataDirectory: URL,
        didCommit: @escaping @Sendable (any GRDBStorable) async -> Void = { _ in }
    ) async throws -> BrainStore {
        BrainStore(
            driver: driver,
            db: try await DB.connect(driver),
            lock: BrainLock(dataDirectory: dataDirectory),
            didCommit: didCommit
        )
    }

    // The lifecycle scope: the schema moves forward and the body runs beside
    // it, under one fence. It is here rather than behind `run` because
    // migrating is not a transaction and must not happen to a caller who only
    // meant to read — init and update are the only two that ask.
    //
    // The body is handed a connection because what it does spans transactions:
    // planting notes and building the index each open their own, and they have
    // to land on the far side of the migration and the near side of the fence.
    public func bootstrap<T>(_ body: (any DatabaseWriter) throws -> T) async throws -> T {
        try await lock.exclusive {
            try driver.migrateSchema()

            let result = try body(try driver.connect())

            await didCommit(self)

            return result
        }
    }

    @discardableResult
    public func run<T: GRDBOperation>(_ operation: T) async throws -> T.Result {
        guard !operation.readOnly else {
            return try await db.run(operation)
        }

        return try await exclusive { try await self.db.run(operation) }
    }

    // The announcement is made in here, after the body and before the fence
    // comes down: outside it another process's committed values could be
    // clobbered by ours, and a cache warmed there would hold what the database
    // never settled on. A body that threw took nothing, so nothing is
    // announced.
    public func exclusive<T>(_ body: @Sendable () async throws -> T) async throws -> T {
        try await lock.exclusive {
            let result = try await body()

            await didCommit(self)

            return result
        }
    }
}
