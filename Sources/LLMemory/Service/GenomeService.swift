//
//  GenomeService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Genome-domain service — plasticity parameter observation surfaces.
public enum GenomeService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func list(_ storage: GRDBStorage) async throws -> [Genome.ListRow] {
        try await storage.run(ListGenesTransaction())
    }

    public static func history(
        _ storage: GRDBStorage,
        gene: String?,
        limit: Int
    ) async throws -> [Genome.HistoryRow] {
        try await storage.run(GeneHistoryTransaction(.init(gene: gene, limit: limit)))
    }

    public static func shadow(
        _ storage: GRDBStorage,
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> Genome.ShadowResult {
        try await storage.run(
            GeneShadowTransaction(
                .init(gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
            )
        )
    }

    // MARK: - Private
}
