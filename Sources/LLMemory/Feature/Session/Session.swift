//
//  Session.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public enum Session {
    // The migration catalogue is assembled here — the process bootstrap is the
    // single place that knows which migrations make up the current brain schema.
    static let migrations: [any GRDBMigration] = [
        Migration1()
    ]

    public static func configure(home: String) {
        let changed = Paths.configure(home: home)

        if changed {
            GRDBStorage.bind(
                session: GRDBStorage(
                    databaseURL: Paths.db,
                    migrations: migrations
                )
            )
            Config.invalidateCache()
        }

        Config.warmCache()
    }
    
    public static func retrievalSession(cli: String?) -> String? {
        Env.retrievalSession(cli: cli)
    }
}
