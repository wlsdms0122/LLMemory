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
//
// It holds contracts, not implementations. This is the one place in the
// package that names a concrete service type — everything downstream sees
// `any XServiceable`, so a collaborator can be swapped or faked without a
// single call site changing, and nothing can quietly reach past a
// contract into an implementation detail.
struct Container: Sendable {
    // MARK: - Property
    let retrieval: any RetrievalServiceable
    let notes: any NotesServiceable
    let stats: any StatsServiceable
    let lint: any LintServiceable
    let enrichment: any EnrichmentServiceable
    let consolidate: any ConsolidateServiceable
    let index: any IndexServiceable
    let genome: any GenomeServiceable
    let operations: any OperationsServiceable

    // MARK: - Initializer
    init(storage: GRDBStorage) {
        let retrieval = RetrievalService(storage: storage)
        let genome = GenomeService(storage: storage, retrieval: retrieval)

        self.retrieval = retrieval
        self.notes = NotesService(storage: storage, retrieval: retrieval)
        self.stats = StatsService(storage: storage)
        self.lint = LintService(storage: storage)
        self.enrichment = EnrichmentService(storage: storage)
        self.consolidate = ConsolidateService(storage: storage, genome: genome)
        self.index = IndexService(storage: storage)
        self.genome = genome
        self.operations = OperationsService(
            storage: storage,
            engine: OperationsEngine(genome: genome)
        )
    }

    // MARK: - Public
    // MARK: - Private
}
