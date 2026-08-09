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
struct BuildIndexTransaction: GRDBTransaction {
    // MARK: - Property
    let rebuild: Bool

    // MARK: - Initializer
    init(rebuild: Bool = false) {
        self.rebuild = rebuild
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Indexer.BuildResult {
        try Indexer.build(db, rebuild: rebuild)
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
    func perform(_ db: Database) throws -> Int {
        try Indexer.reindexFiles(db, filePaths: filePaths)
    }

    // MARK: - Private
}

struct CheckIntegrityTransaction: GRDBTransaction {
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
