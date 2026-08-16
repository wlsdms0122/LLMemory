//
//  PruneResolvedRippleFlagsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct PruneResolvedRippleFlagsTransaction: GRDBTransaction {
    // MARK: - Property
    let now: Int
    let retentionDays: Int

    // MARK: - Initializer
    init(now: Int, retentionDays: Int = 30) {
        self.now = now
        self.retentionDays = retentionDays
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        let cutoff = now - retentionDays * 86400
        
        try db.execute(
            sql: "DELETE FROM ripple_flags WHERE resolved_at IS NOT NULL AND resolved_at < ?",
            arguments: [cutoff]
        )
        
        return db.changesCount
    }

    // MARK: - Private
}
