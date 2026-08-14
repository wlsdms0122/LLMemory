//
//  ValidateTermsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

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
