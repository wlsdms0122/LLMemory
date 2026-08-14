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
// setGene/resetGene are the one write path for a gene value, and they take a
// scope because their callers (the homeostasis tick, the set_gene handler)
// are already inside one.
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

    func history(
        _ scope: GRDBReadScope,
        gene: String?,
        limit: Int
    ) throws -> [GeneHistoryRow]

    func shadow(
        _ scope: GRDBReadScope,
        gene: String,
        value: Double,
        limit: Int,
        sampleDiffs: Int
    ) throws -> GenomeShadowResult

    @discardableResult
    func setGene(
        _ scope: GRDBScope,
        id: String,
        value: Double,
        cause: String,
        detail: String?,
        requireMutable: Bool,
        now: Int
    ) throws -> (old: Double, new: Double)

    @discardableResult
    func resetGene(
        _ scope: GRDBScope,
        id: String,
        cause: String,
        now: Int
    ) throws -> Double
}
