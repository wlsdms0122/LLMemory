//
//  GenomeShadowResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

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
