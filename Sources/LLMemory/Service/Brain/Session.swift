//
//  Session.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

// The state binding for one brain home — paths, store and warmed parameter
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
    public let store: BrainStore
    let context: BrainContext

    private let indexer = Indexer()

    // MARK: - Initializer
    private init(home: URL, store: BrainStore, context: BrainContext) {
        self.home = home
        self.store = store
        self.context = context
    }

    // MARK: - Public
    // Binds a brain that already exists. A home whose database is missing or
    // whose migrations are pending refuses here rather than being carried
    // forward — moving a brain's schema is `Bootstrap`, and it happens only
    // where someone asked for it.
    public static func open(home: String) async throws -> Session {
        let context = BrainContext(home: home)
        let store = try await BrainStore.open(
            GRDBStorage(databaseURL: context.layout.db, migrations: migrations),
            dataDirectory: context.layout.dataDirectory,
            // The store does not know what a brain is — it reports that the
            // answer to "what is committed" moved, and the caches follow.
            didCommit: { store in await context.reloadCommitted(store) }
        )

        await context.reloadCommitted(store)

        return Session(home: context.home, store: store, context: context)
    }

    // Re-warms the parameter caches from the database — required after the
    // database first comes into existence or migrates (init/update), since
    // opening may have warmed against a database that was not there yet.
    public func rewarm() async {
        await context.reloadCommitted(store)
    }

    // The init/update bootstrap. It is the one lifecycle boundary that runs
    // *before* the migration gate can pass, so it goes through the store's
    // bootstrap scope rather than through `run`.
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
    ) async throws -> Indexer.BuildResult {
        try await store.bootstrap { queue in
            // Opening may have warmed against a database that was not there
            // yet — re-warm before anything below reads the caches.
            try queue.read { db in try context.loadCommitted(db) }

            try beforeIndexing(BootstrapScope(queue: queue, context: context))

            return try indexer.buildLocked(queue, context, rebuild: false)
        }
    }

    // MARK: - Private
}
