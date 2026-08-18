//
//  CompactOldEventsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Consolidation hygiene operations — retention compaction, prune passes,
// integrity probes, and the tag report.
struct CompactOldEventsOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (Int, Int)
    let now: Int
    let retentionSec: Int

    // MARK: - Initializer
    init(now: Int, retentionSec: Int) {
        self.now = now
        self.retentionSec = retentionSec
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> (compacted: Int, days: Int) {
        let cutoff = now - retentionSec
        
        try db.execute(sql: "DELETE FROM events WHERE ts < ?", arguments: [cutoff])
        
        return (db.changesCount, 0)
    }

    // MARK: - Private
}
