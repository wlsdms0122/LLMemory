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
// caller that only holds the contract can still ask what it may ask for.
// The scope-taking cores are on the contract for the same reason as the
// async wrappers above them: they are what a caller inside an open scope
// composes with.
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

    func integrate(_ scope: GRDBScope) throws -> IntegrateResult

    func prune(_ scope: GRDBScope) throws -> PruneResult

    func homeostasisTick(_ scope: GRDBScope, now: Int) throws -> HomeostasisReport
}
