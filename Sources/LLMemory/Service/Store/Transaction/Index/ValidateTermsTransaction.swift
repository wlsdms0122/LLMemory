//
//  ValidateTermsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ValidateTermsTransaction: GRDBBrainTransaction {
    // MARK: - Property
    let rejectStale: Bool
    let keywords: any KeywordExtracting

    // MARK: - Initializer
    init(rejectStale: Bool, keywords: any KeywordExtracting) {
        self.rejectStale = rejectStale
        self.keywords = keywords
    }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> Indexer.ValidateResult {
        let pass = try ValidatePendingTermsTransaction(noteIds: nil, keywords: keywords).perform(db, brain)
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
