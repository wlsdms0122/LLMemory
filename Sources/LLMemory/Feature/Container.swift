//
//  Container.swift
//  LLMemory
//
//  Created by JSilver on 8/10/26.
//

import Foundation

// The dependency container — the single wiring point for services.
// Cross-service collaborators are injected here, so no service (and no
// handler) ever reaches for a sibling through a global. The invariant is
// *where wiring happens*, not instance count: services are stateless
// values over storage, so assembling the container twice is semantically
// the same container (which is exactly what test fixtures do). Owned by
// Brain, the composition root; features receive only what they need.
public struct Container: Sendable {
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
        let lint = LintService(storage: storage)

        self.retrieval = retrieval
        self.notes = NotesService(storage: storage, retrieval: retrieval)
        self.stats = StatsService(storage: storage)
        self.lint = lint
        self.enrichment = EnrichmentService(storage: storage)
        self.consolidate = ConsolidateService(storage: storage, genome: genome)
        self.index = IndexService(storage: storage)
        self.genome = genome
        self.ruleset = ruleset
        self.operations = OperationsService(
            storage: storage,
            engine: OperationsEngine(genome: genome, ruleset: ruleset, lint: lint)
        )
    }

    // MARK: - Public
    // MARK: - Private
}
