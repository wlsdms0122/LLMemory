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
    let keywords: any KeywordExtracting
    let roundtripTopK: Int
    let idfDFCeiling: Double

    // MARK: - Initializer
    init(
        rejectStale: Bool,
        keywords: any KeywordExtracting,
        roundtripTopK: Int,
        idfDFCeiling: Double
    ) {
        self.rejectStale = rejectStale
        self.keywords = keywords
        self.roundtripTopK = roundtripTopK
        self.idfDFCeiling = idfDFCeiling
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Indexer.ValidateResult {
        let pass = try ValidatePendingTermsTransaction(
            noteIds: nil,
            keywords: keywords,
            roundtripTopK: roundtripTopK,
            idfDFCeiling: idfDFCeiling
        )
            .perform(db)
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
