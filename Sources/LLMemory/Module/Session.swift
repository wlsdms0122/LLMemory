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

    // MARK: - Initializer
    public init(home: String) {
        // Paths and the Config/Genome caches are still process-global remnants —
        // services read them ambiently. One live Session per process until they
        // move onto this instance.
        Paths.configure(home: home)

        self.home = Paths.brainRoot
        self.storage = GRDBStorage(
            databaseURL: Paths.db,
            migrations: Self.migrations
        )

        Config.invalidateCache()
        Config.warmCache(storage)
    }

    // MARK: - Public
    // Re-warms the parameter caches from the database — required after the
    // database first comes into existence or migrates (init/update), since the
    // constructor may have warmed against a database that was not there yet.
    public func rewarm() {
        Config.invalidateCache()
        Config.warmCache(storage)
    }

    public static func retrievalSession(cli: String?) -> String? {
        Env.retrievalSession(cli: cli)
    }

    // MARK: - Private
}
