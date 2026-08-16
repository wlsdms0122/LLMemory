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
    let enrichment: EnrichmentTuning

    // MARK: - Initializer
    init(rejectStale: Bool, keywords: any KeywordExtracting, enrichment: EnrichmentTuning) {
        self.rejectStale = rejectStale
        self.keywords = keywords
        self.enrichment = enrichment
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Indexer.ValidateResult {
        let pass = try ValidatePendingTermsTransaction(
            noteIds: nil,
            keywords: keywords,
            roundtripTopK: enrichment.roundtripTopK,
            idfDFCeiling: enrichment.idfDFCeiling
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
