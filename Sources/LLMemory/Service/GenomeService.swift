//
//  GenomeService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Genome-domain service — owns the plasticity-parameter rules (bounds,
// mutability, integer genes) and the observation surfaces. DB touches ride
// genome transactions; the code-owned catalog and value cache live in the
// Genome module.
public enum GenomeService {
    public enum WriteError: Error, CustomStringConvertible {
        case unknownGene(String)
        case outOfBounds(String, Double, Genome.Gene)
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

    public struct ListRow: Encodable, Sendable {
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

    public struct HistoryRow: Encodable, Sendable {
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

    public struct ShadowResult: Encodable, Sendable {
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

    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    // Rewarms the value cache from the DB before mapping, so the listing
    // reflects the brain's epigenome (and keeps the connection gate — an
    // uninitialized brain fails loud instead of masquerading as wild-type).
    public static func list(_ storage: GRDBStorage) async throws -> [ListRow] {
        try await storage.read { scope in
            Genome.warm(try scope.run(FetchGenomeValuesTransaction()))

            return list()
        }
    }

    public static func history(
        _ storage: GRDBStorage,
        gene: String?,
        limit: Int
    ) async throws -> [HistoryRow] {
        try await storage.read { scope in
            try history(scope, gene: gene, limit: limit)
        }
    }

    public static func shadow(
        _ storage: GRDBStorage,
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> ShadowResult {
        try await storage.run(
            GeneShadowTransaction(
                .init(gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
            )
        )
    }

    // MARK: - Internal
    static func list() -> [ListRow] {
        Genome.catalog.map { gene in
            ListRow(
                id: gene.id,
                value: Genome.double(gene.id),
                wildType: gene.wildType,
                min: gene.min,
                max: gene.max,
                mutable: gene.mutable,
                source: Genome.source(gene.id),
                summary: gene.summary
            )
        }
    }

    static func history(
        _ scope: GRDBScope,
        gene: String?,
        limit: Int
    ) throws -> [HistoryRow] {
        try scope.run(FetchGenomeEventsTransaction(geneId: gene, limit: limit))
            .map { event in
                HistoryRow(
                    geneId: event.geneId,
                    oldValue: event.oldValue,
                    newValue: event.newValue,
                    cause: event.cause,
                    detail: event.detail,
                    ts: event.ts
                )
            }
    }

    // The one write path for gene values — validates against the code-owned
    // declaration, records provenance, and keeps the in-process cache honest.
    @discardableResult
    static func setGene(
        _ scope: GRDBScope,
        id: String,
        value: Double,
        cause: String,
        detail: String?,
        requireMutable: Bool,
        now: Int
    ) throws -> (old: Double, new: Double) {
        guard let gene = Genome.gene(id) else { throw WriteError.unknownGene(id) }

        if requireMutable && !gene.mutable { throw WriteError.locked(id) }

        guard value >= gene.min && value <= gene.max else {
            throw WriteError.outOfBounds(id, value, gene)
        }

        if gene.integer && value != value.rounded() {
            throw WriteError.notInteger(id, value)
        }

        let old = Genome.cached(id) ?? Config.getDouble(id, default: gene.wildType)

        try scope.run(
            SetGeneTransaction(
                geneId: id,
                value: value,
                oldValue: old,
                cause: cause,
                detail: detail,
                ts: now
            )
        )

        Genome.prime(id, value)

        return (old, value)
    }

    @discardableResult
    static func resetGene(
        _ scope: GRDBScope,
        id: String,
        cause: String,
        now: Int
    ) throws -> Double {
        guard let gene = Genome.gene(id) else { throw WriteError.unknownGene(id) }

        let old = Genome.cached(id) ?? Config.getDouble(id, default: gene.wildType)

        try scope.run(
            ResetGeneTransaction(
                geneId: id,
                oldValue: old,
                wildType: gene.wildType,
                cause: cause,
                ts: now
            )
        )

        Genome.prime(id, nil)

        return old
    }

    // MARK: - Private
}
