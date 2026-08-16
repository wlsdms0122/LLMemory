//
//  ReconcileIndexTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Index maintenance — full build/reconcile, targeted reindex, and the
// integrity check. These conform to the store's transaction protocol but
// belong to the index domain, which is why they sit here and not under
// Store: what a correct projection of the corpus looks like is Indexer's
// judgement, and it needs the brain to make it.
struct ReconcileIndexTransaction: GRDBTransaction {
    // MARK: - Property
    let brain: BrainContext
    let scan: Indexer.Scan
    let rebuild: Bool
    let now: Int

    private let indexer = Indexer()

    // MARK: - Initializer
    init(brain: BrainContext, scan: Indexer.Scan, rebuild: Bool = false, now: Int) {
        self.brain = brain
        self.scan = scan
        self.rebuild = rebuild
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Indexer.BuildResult {
        try indexer.reconcile(
            brain,
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
