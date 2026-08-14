//
//  ReconcileIndexTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Index maintenance transactions — full build/reconcile, targeted reindex,
// integrity check, and enrichment-term validation.
struct ReconcileIndexTransaction: GRDBTransaction {
    // MARK: - Property
    let scan: Indexer.Scan
    let rebuild: Bool
    let now: Int

    // MARK: - Initializer
    init(scan: Indexer.Scan, rebuild: Bool = false, now: Int) {
        self.scan = scan
        self.rebuild = rebuild
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Indexer.BuildResult {
        try Indexer.reconcile(
            db,
            pending: scan.pending,
            scannedRels: scan.scannedRels,
            rebuild: rebuild,
            now: now,
            fileErrors: scan.errors
        )
    }

    // MARK: - Private
}
