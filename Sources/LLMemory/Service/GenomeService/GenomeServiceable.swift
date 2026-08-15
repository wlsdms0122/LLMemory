//
//  GenomeServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The plasticity parameters — the catalog with this brain's current values,
// the provenance of every mutation, and offline reranking under a candidate
// value.
//
// Writing a gene value is not here: every caller of it is already inside a
// unit of work and needs the change to belong to that unit, which makes it
// a transaction (ApplyGeneValueTransaction), not a feature of this service.
protocol GenomeServiceable: Sendable {
    func list() async throws -> [GeneListRow]

    func history(
        gene: String?,
        limit: Int
    ) async throws -> [GeneHistoryRow]

    func shadow(
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) async throws -> GenomeShadowResult
}
