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

    // MARK: - Initializer
    public init(home: String) {
        // The context carries this brain's paths and parameter caches; the
        // storage binds it around every scope. It also becomes the process
        // fallback so ambient reads outside any scope (file walks before a
        // scope opens, CLI startup) keep resolving in single-brain flows.
        let context = BrainContext(home: home)

        BrainContext.adoptFallback(context)

        self.context = context
        self.home = context.home
        self.storage = GRDBStorage(
            databaseURL: context.home.appendingPathComponent("data/memory.db"),
            migrations: Self.migrations,
            context: context
        )

        context.bind { Config.invalidateCache() }
        Config.warmCache(storage)
    }

    // MARK: - Public
    // Re-warms the parameter caches from the database — required after the
    // database first comes into existence or migrates (init/update), since the
    // constructor may have warmed against a database that was not there yet.
    public func rewarm() {
        context.bind { Config.invalidateCache() }
        Config.warmCache(storage)
    }

    // The init/update bootstrap — the one lifecycle boundary allowed to touch
    // storage directly, because it runs *before* the migration gate can pass:
    // migrate, re-warm the caches, then bring the index up under the write lock.
    public func bootstrap() throws -> Indexer.BuildResult {
        try storage.writeLock {
            try storage.initialize()

            // The constructor may have warmed against a database that was not
            // there yet — re-warm before anything below reads the caches.
            rewarm()

            let queue = try storage.connect()
            let built = try Indexer.buildLocked(queue, rebuild: false)

            try queue.write { db in try Seeding.describeInnateAxis(db) }

            return built
        }
    }

    public static func retrievalSession(cli: String?) -> String? {
        Env.retrievalSession(cli: cli)
    }

    // MARK: - Private
}
