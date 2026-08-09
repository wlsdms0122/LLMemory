//
//  Genome.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Genome {
    // MARK: - Property
    let genome: GenomeService

    // MARK: - Initializer
    init(genome: GenomeService) {
        self.genome = genome
    }

    // MARK: - Public
    public func list() async throws -> [GenomeService.ListRow] {
        try await genome.list()
    }

    public func history(
        gene: String?,
        limit: Int
    ) async throws -> [GenomeService.HistoryRow] {
        try await genome.history(gene: gene, limit: limit)
    }

    public func shadow(
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> GenomeService.ShadowResult {
        try await genome.shadow(gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
    }

    // MARK: - Private
}
