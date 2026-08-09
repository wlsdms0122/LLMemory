//
//  Services.swift
//  LLMemory
//
//  Created by JSilver on 8/10/26.
//

import Foundation

// The dependency container — the one place service instances are assembled.
// Cross-service collaborators are wired here by injection, so no service
// (and no handler) ever reaches for a sibling through a global. Owned by
// Brain, the composition root; features receive only what they need.
public struct Services: Sendable {
    // MARK: - Property
    public let retrieval: RetrievalService
    public let notes: NotesService
    public let stats: StatsService
    public let lint: LintService
    public let enrichment: EnrichmentService
    public let consolidate: ConsolidateService
    public let index: IndexService
    public let genome: GenomeService
    public let ruleset: RulesetService
    public let operations: OperationsService

    // MARK: - Initializer
    init(storage: GRDBStorage) {
        let retrieval = RetrievalService(storage: storage)
        let genome = GenomeService(storage: storage, retrieval: retrieval)
        let ruleset = RulesetService(storage: storage)

        self.retrieval = retrieval
        self.notes = NotesService(storage: storage, retrieval: retrieval)
        self.stats = StatsService(storage: storage)
        self.lint = LintService(storage: storage)
        self.enrichment = EnrichmentService(storage: storage)
        self.consolidate = ConsolidateService(storage: storage, genome: genome)
        self.index = IndexService(storage: storage)
        self.genome = genome
        self.ruleset = ruleset
        self.operations = OperationsService(
            storage: storage,
            engine: OperationsEngine(genome: genome, ruleset: ruleset)
        )
    }

    // MARK: - Public
    // MARK: - Private
}
