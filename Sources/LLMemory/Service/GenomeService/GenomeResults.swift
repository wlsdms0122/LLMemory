//
//  GenomeResults.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The genome surface vocabulary — flat top-level models with a domain
// prefix (owner call: a caller must not need the service's name to spell
// a return type). Errors are flat too, like CandidatesError.
public enum GenomeWriteError: Error, CustomStringConvertible {
    case unknownGene(String)
    case outOfBounds(String, Double, Genes.Gene)
    case notInteger(String, Double)
    case locked(String)

    public var description: String {
        switch self {
        case .unknownGene(let id):
            return "unknown gene: '\(id)' — see `genome list` for the catalog"

        case .outOfBounds(let id, let value, let gene):
            return "gene '\(id)' value \(value) is outside bounds [\(gene.min), \(gene.max)]"

        case .notInteger(let id, let value):
            return "gene '\(id)' takes whole numbers — got \(value)"

        case .locked(let id):
            return "gene '\(id)' is locked (write-path) — homeostasis may not adjust it"
        }
    }
}

public struct GeneListRow: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id, value
        case wildType = "wild_type"
        case min, max, mutable, source, summary
    }

    // MARK: - Property
    public let id: String
    public let value: Double
    public let wildType: Double
    public let min: Double
    public let max: Double
    public let mutable: Bool
    public let source: String
    public let summary: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct GeneHistoryRow: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case geneId = "gene_id"
        case oldValue = "old_value"
        case newValue = "new_value"
        case cause, detail, ts
    }

    // MARK: - Property
    public let geneId: String
    public let oldValue: Double?
    public let newValue: Double
    public let cause: String
    public let detail: String?
    public let ts: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct GenomeShadowResult: Encodable, Sendable {
    public struct QueryDiff: Encodable, Sendable {
        // MARK: - Property
        public let query: String
        public let baseline: [String]
        public let candidate: [String]
        public let entered: [String]
        public let dropped: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    enum CodingKeys: String, CodingKey {
        case gene
        case baselineValue = "baseline_value"
        case candidateValue = "candidate_value"
        case queriesReplayed = "queries_replayed"
        case queriesChanged = "queries_changed"
        case diffs
    }

    // MARK: - Property
    public let gene: String
    public let baselineValue: Double
    public let candidateValue: Double
    public let queriesReplayed: Int
    public let queriesChanged: Int
    public let diffs: [QueryDiff]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
