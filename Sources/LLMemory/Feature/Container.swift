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
    init(storage: GRDBStorage, brain: BrainContext) {
        // The retrieval strategies are chosen once, here, and handed to
        // everything that reads text for cues. Swapping either one is this
        // line and nothing else — which is the whole reason they are named by
        // what they answer rather than by how they answer it.
        let keywords: any KeywordExtracting = FrequencyKeywordExtractor()
        let entities: any EntityHinting = PatternEntityHinter()
        let retrieval = RetrievalService(storage: storage, brain: brain, keywords: keywords, entities: entities)
        let genome = GenomeService(storage: storage, brain: brain, keywords: keywords, entities: entities)
        let scanner = LintScanner(rules: LintRuleRegistry())
        let lint = LintService(storage: storage, brain: brain, scanner: scanner)

        self.retrieval = retrieval
        self.notes = NotesService(storage: storage, brain: brain, retrieval: retrieval)
        self.stats = StatsService(storage: storage)
        self.lint = lint
        self.enrichment = EnrichmentService(storage: storage, brain: brain)
        self.consolidate = ConsolidateService(storage: storage, brain: brain, keywords: keywords)
        self.index = IndexService(storage: storage, brain: brain, keywords: keywords)
        self.genome = genome
        self.operations = OperationsService(
            storage: storage,
            engine: OperationsEngine(lint: scanner, keywords: keywords, brain: brain)
        )
    }

    // MARK: - Public
    // MARK: - Private
}
