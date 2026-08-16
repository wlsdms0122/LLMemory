//
//  ConsolidateServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Periodic tidying, separated by concern because the cadences differ:
// integrate (non-destructive, often), prune (synaptic decay, rarely),
// homeostasis (a metaplasticity tick), and the candidate surfaces that
// report what tidying would find.
//
// The kind vocabularies are instance members rather than type members so a
// caller that only holds the contract can still ask what it may ask for —
// the surface that validates a `--kind` argument and the surface that
// consumes it are then the same surface.
protocol ConsolidateServiceable: Sendable {
    var candidateRetrievalKinds: [String] { get }
    var candidateStructuralKinds: [String] { get }
    var candidateValidKinds: [String] { get }

    func candidates(
        kinds: [String],
        limit: Int
    ) async throws -> [String: CandidateBatch]

    func integrate() async throws -> IntegrateResult

    func homeostasis() async throws -> HomeostasisReport

    func prune() async throws -> PruneResult

    func report() async throws -> ConsolidateTagReport
}
