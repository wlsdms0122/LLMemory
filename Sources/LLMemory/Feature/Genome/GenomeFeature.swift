//
//  GenomeFeature.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import Storage

public struct GenomeFeature {
    // MARK: - Property
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public
    public func list() async throws -> [Genome.ListRow] {
        try await session.storage.run(ListGenesTransaction())
    }

    public func history(
        gene: String?,
        limit: Int
    ) async throws -> [Genome.HistoryRow] {
        try await session.storage.run(GeneHistoryTransaction(.init(gene: gene, limit: limit)))
    }

    public func shadow(
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> Genome.ShadowResult {
        try await session.storage.run(
            GeneShadowTransaction(
                .init(gene: gene, value: value, limit: limit, sampleDiffs: sampleDiffs)
            )
        )
    }

    // MARK: - Private
}
