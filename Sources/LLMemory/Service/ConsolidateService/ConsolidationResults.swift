//
//  ConsolidationResults.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// Consolidation result shapes — reports and summaries the consolidate
// service returns, flat top-level models like the other service results.
// The canonical axis/tag report rows — encoded as compact arrays
// ([axis, description, count]), shared by every reporting surface.
public struct AxisRow: Encodable, Sendable {
    // MARK: - Property
    public let axis: String
    public let description: String?
    public let count: Int

    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()

        try container.encode(axis)

        if let description {
            try container.encode(description)
        } else {
            try container.encodeNil()
        }

        try container.encode(count)
    }

    // MARK: - Private
}

public struct AxisCount: Encodable, Sendable {
    // MARK: - Property
    public let axis: String
    public let count: Int

    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()

        try container.encode(axis)
        try container.encode(count)
    }

    // MARK: - Private
}

public struct TagCount: Encodable, Sendable {
    // MARK: - Property
    public let tag: String
    public let count: Int

    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()

        try container.encode(tag)
        try container.encode(count)
    }

    // MARK: - Private
}

public struct ConsolidateAxisReport: Encodable, Sendable {
    // MARK: - Property
    public let all: [AxisRow]
    public let small: [AxisCount]
    public let large: [AxisCount]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct ConsolidateTagReport: Encodable, Sendable {
    // MARK: - Property
    public let rare: [TagCount]
    public let unused: [String]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct IntegrateResult: Encodable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case summary
        case axisReport = "axis_report"
        case tagReport = "tag_report"
        case prune
        case integrityL1 = "integrity_l1"
    }

    public struct Summary: Encodable, Sendable {
        public enum CodingKeys: String, CodingKey {
            case eventsCompacted = "events_compacted"
            case smallAxes = "small_axes"
            case largeAxes = "large_axes"
            case rareTags = "rare_tags"
            case unusedVocabTags = "unused_vocab_tags"
            case emptyAxesPruned = "empty_axes_pruned"
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
        public let smallAxes: Int
        public let largeAxes: Int
        public let rareTags: Int
        public let unusedVocabTags: Int
        public let emptyAxesPruned: Int
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
            case axes
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
        public let axes: GroupReport
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
    public let axisReport: ConsolidateAxisReport
    public let tagReport: ConsolidateTagReport
    public let prune: PruneReport
    public var integrityL1: IntegrityReport

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct PruneResult: Encodable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case linksDecayed = "links_decayed"
        case linksPruned = "links_pruned"
    }

    // MARK: - Property
    public let linksDecayed: Int
    public let linksPruned: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct HomeostasisReport: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case windowsProcessed = "windows_processed"
        case expandSeen = "expand_seen"
        case expandLanded = "expand_landed"
        case sampleSeen = "sample_seen"
        case sampleLanded = "sample_landed"
        case evaluated
        case landingRate = "landing_rate"
        case adjustedGene = "adjusted_gene"
        case oldValue = "old_value"
        case newValue = "new_value"
        case note
    }

    // MARK: - Property
    public let windowsProcessed: Int
    public let expandSeen: Int
    public let expandLanded: Int
    public let sampleSeen: Int
    public let sampleLanded: Int
    public let evaluated: Bool
    public let landingRate: Double?
    public let adjustedGene: String?
    public let oldValue: Double?
    public let newValue: Double?
    public let note: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
