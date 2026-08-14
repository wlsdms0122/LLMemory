//
//  Genome.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Genome {
    // MARK: - Property
    let service: any GenomeServiceable

    // MARK: - Initializer
    init(service: any GenomeServiceable) {
        self.service = service
    }

    // MARK: - Public
    public func list() async throws -> [GeneListRow] {
        try await service.list()
    }

    public func history(
        gene: String?,
        limit: Int
    ) async throws -> [GeneHistoryRow] {
        try await service.history(gene: gene, limit: limit)
    }

    public func shadow(
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> GenomeShadowResult {
        try await service.shadow(gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
    }

    // MARK: - Private
}
