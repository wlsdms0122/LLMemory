//
//  CandidateBatchTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Consolidation candidate surfacing — one batch per requested kind.
struct FetchCandidateBatchesTransaction: GRDBTransaction {
    // MARK: - Property
    let kinds: [String]
    let limit: Int

    // MARK: - Initializer
    init(kinds: [String], limit: Int) {
        self.kinds = kinds
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: Candidates.Batch] {
        var batches: [String: Candidates.Batch] = [:]

        for kind in kinds { batches[kind] = try batchForKind(db, kind) }

        return batches
    }

    // MARK: - Private
    private func batchForKind(_ db: Database, _ kind: String) throws -> Candidates.Batch {
        switch kind {
        case "split":
            return .split(try Candidates.splitCandidates(db, limit: limit))

        case "reconsolidate":
            return .flagged(try Candidates.reconsolidateCandidates(db, limit: limit))

        case "ripple":
            return .flagged(try Candidates.rippleCandidates(db, limit: limit))

        case "enrich_review":
            return .flagged(try Candidates.enrichReviewCandidates(db, limit: limit))

        case "clusters":
            return .clusters(try Candidates.clusters(db, limit: limit))

        case "missing_edge":
            return .missingEdge(try Candidates.missingEdges(db, limit: limit))

        case "near_duplicate":
            return .nearDuplicate(try Candidates.nearDuplicates(db, limit: limit))

        default:
            return .split([])
        }
    }
}
