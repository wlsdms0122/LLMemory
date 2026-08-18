//
//  PruneOldLifecycleEventsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct PruneOldLifecycleEventsOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (Int, Int)
    let now: Int
    let retentionDays: Int

    // MARK: - Initializer
    init(now: Int, retentionDays: Int = 180) {
        self.now = now
        self.retentionDays = retentionDays
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> Int {
        let cutoff = now - retentionDays * 86400
        
        try db.execute(
            sql: "DELETE FROM note_lifecycle_events WHERE created_at < ?",
            arguments: [cutoff]
        )
        
        return db.changesCount
    }

    // MARK: - Private
}
