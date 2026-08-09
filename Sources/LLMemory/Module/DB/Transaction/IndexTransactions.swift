//
//  IndexTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
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

struct ReindexNotesTransaction: GRDBTransaction {
    // MARK: - Property
    let filePaths: [String]

    // MARK: - Initializer
    init(filePaths: [String]) {
        self.filePaths = filePaths
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Indexer.ReindexOutcome] {
        try Indexer.reindexFiles(db, filePaths: filePaths)
    }

    // MARK: - Private
}

struct CheckIntegrityTransaction: GRDBReadTransaction {
    // MARK: - Property
    let level: Indexer.IntegrityLevel

    // MARK: - Initializer
    init(level: Indexer.IntegrityLevel = .l1) {
        self.level = level
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (ok: Bool, msgs: [String]) {
        try Indexer.check(db, rawLevel: level.rawValue)
    }

    // MARK: - Private
}

struct ValidateTermsTransaction: GRDBTransaction {
    // MARK: - Property
    let rejectStale: Bool

    // MARK: - Initializer
    init(rejectStale: Bool) {
        self.rejectStale = rejectStale
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Indexer.ValidateResult {
        let pass = try ValidatePendingTermsTransaction(noteIds: nil).perform(db)
        let staleRejected = rejectStale ? try RejectStalePendingTermsTransaction().perform(db) : 0

        return Indexer.ValidateResult(
            activated: pass.activated,
            rejected: pass.rejected,
            stillPending: pass.stillPending,
            staleRejected: staleRejected,
            rejectBreakdown: pass.rejectBreakdown
        )
    }

    // MARK: - Private
}
