//
//  GenomeFeature.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct GenomeFeature {
    // MARK: - Property
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public
    public func list() async throws -> [Genome.ListRow] {
        try await GenomeService.list(session.storage)
    }

    public func history(
        gene: String?,
        limit: Int
    ) async throws -> [Genome.HistoryRow] {
        try await GenomeService.history(session.storage, gene: gene, limit: limit)
    }

    public func shadow(
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> Genome.ShadowResult {
        try await GenomeService.shadow(session.storage, gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
    }

    // MARK: - Private
}
