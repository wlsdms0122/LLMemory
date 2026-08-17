//
//  Session.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// The state binding for one brain home — paths, storage and warmed parameter
// caches share a lifetime here. Constructed once at the composition root
// (`Brain`); everything below receives what it needs explicitly.
public final class Session {
    // MARK: - Property
    // The migration catalogue is assembled here — the state binding is the
    // single place that knows which migrations make up the current brain schema.
    static let migrations: [any GRDBMigration] = [
        Migration1()
    ]

    public let home: URL
    public let storage: GRDBStorage
    let context: BrainContext

    private let indexer = Indexer()


    // MARK: - Initializer
    public init(home: String) {
        // The context carries this brain's paths and parameter caches. The
        // storage does not hold it — it only reports that committed state
        // changed, and the caches follow.
        let context = BrainContext(home: home)

        self.context = context
        self.home = context.home
        self.storage = GRDBStorage(
            databaseURL: context.layout.db,
            migrations: Self.migrations,
            didCommit: { storage in context.reloadCommitted(storage) }
        )

        context.reloadCommitted(storage)
    }

    // MARK: - Public
    // Re-warms the parameter caches from the database — required after the
    // database first comes into existence or migrates (init/update), since the
    // constructor may have warmed against a database that was not there yet.
    public func rewarm() {
        context.reloadCommitted(storage)
    }

    // The init/update bootstrap — the one lifecycle boundary allowed to touch
    // storage directly, because it runs *before* the migration gate can pass:
    // migrate, re-warm the caches, then bring the index up under the write lock.
    //
    // `beforeIndexing` is where init/update write to the cortex. Taking it as a
    // closure rather than letting the caller sequence the two is what puts those
    // writes on the far side of the migration — a failed migration must not leave
    // a brain whose files moved forward and whose schema did not — and on the near
    // side of the build, so what it writes is indexed by the same pass.
    //
    // It is handed a scope over the migrated brain: what the catalog knows before
    // this run's changes — enough to find the notes an earlier release left
    // behind, and stale enough that the files themselves settle every decision —
    // and the shared way a note leaves the corpus.
    @discardableResult
    public func bootstrap(
        beforeIndexing: (BootstrapScope) throws -> Void = { _ in }
    ) throws -> Indexer.BuildResult {
        try storage.writeLock {
            try storage.prepare()

            // The constructor may have warmed against a database that was not
            // there yet — re-warm before anything below reads the caches.
            rewarm()

            let queue = try storage.connect()

            try beforeIndexing(BootstrapScope(queue: queue, context: context))

            let built = try indexer.buildLocked(queue, context, rebuild: false)

            return built
        }
    }

    // MARK: - Private
}
