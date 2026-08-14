//
//  IntegrateResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct IntegrateResult: Encodable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case summary
        case tagReport = "tag_report"
        case prune
        case integrityL1 = "integrity_l1"
    }

    public struct Summary: Encodable, Sendable {
        public enum CodingKeys: String, CodingKey {
            case eventsCompacted = "events_compacted"
            case rareTags = "rare_tags"
            case unusedVocabTags = "unused_vocab_tags"
            case unusedVocabPruned = "unused_vocab_pruned"
            case resolvedRipplePruned = "resolved_ripple_pruned"
            case ftsOrphansPruned = "fts_orphans_pruned"
            case ftsRefilled = "fts_refilled"
            case integrityL1Issues = "integrity_l1_issues"
            case linksDecayed = "links_decayed"
            case linksPruned = "links_pruned"
            case sourcesRechecked = "sources_rechecked"
            case sourcesBecameStale = "sources_became_stale"
            case sourcesRecovered = "sources_recovered"
            case sourcesMissing = "sources_missing"
            case sourcesUnreadable = "sources_unreadable"
            case termsActivated = "terms_activated"
            case termsRejected = "terms_rejected"
            case enrichReviewFlagged = "enrich_review_flagged"
            case enrichReviewResolved = "enrich_review_resolved"
            case vectorsBuilt = "vectors_built"
            case degradedPasses = "degraded_passes"
        }

        // MARK: - Property
        public let eventsCompacted: Int
        public let rareTags: Int
        public let unusedVocabTags: Int
        public let unusedVocabPruned: Int
        public let resolvedRipplePruned: Int
        public let ftsOrphansPruned: Int
        public let ftsRefilled: Int
        public var integrityL1Issues: Int
        public let linksDecayed: Int
        public let linksPruned: Int
        public let sourcesRechecked: Int
        public let sourcesBecameStale: Int
        public let sourcesRecovered: Int
        public let sourcesMissing: Int
        public let sourcesUnreadable: Int
        public let termsActivated: Int
        public let termsRejected: Int
        public let enrichReviewFlagged: Int
        public let enrichReviewResolved: Int
        public let vectorsBuilt: Int
        // Best-effort passes that failed and rolled back, by name —
        // distinguishes "nothing to do" from "pass degraded".
        public let degradedPasses: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    public struct PruneReport: Encodable, Sendable {
        public enum CodingKeys: String, CodingKey {
            case tagVocab = "tag_vocab"
        }

        public struct GroupReport: Encodable, Sendable {
            // MARK: - Property
            public let pruned: [String]
            public let count: Int

            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }

        // MARK: - Property
        public let tagVocab: GroupReport

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    public struct IntegrityReport: Encodable, Sendable {
        // MARK: - Property
        public let checked: Int
        public let issues: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    public var summary: Summary
    public let tagReport: ConsolidateTagReport
    public let prune: PruneReport
    public var integrityL1: IntegrityReport

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
