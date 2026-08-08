//
//  GenomeFeature.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import Storage

public enum GenomeFeature {
    public struct ShadowResult: Encodable {
        public struct QueryDiff: Encodable {
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
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func list(home: String) async throws -> [Genome.ListRow] {
        Session.configure(home: home)

        return try await GRDBStorage.session.run(ListGenesTransaction())
    }

    public static func history(
        home: String,
        gene: String?,
        limit: Int
    ) async throws -> [Genome.HistoryRow] {
        Session.configure(home: home)

        return try await GRDBStorage.session.run(GeneHistoryTransaction(.init(gene: gene, limit: limit)))
    }

    public static func shadow(
        home: String,
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> ShadowResult {
        Session.configure(home: home)

        return try await GRDBStorage.session.run(
            GeneShadowTransaction(
                .init(gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
            )
        )
    }

    // MARK: - Private
}
