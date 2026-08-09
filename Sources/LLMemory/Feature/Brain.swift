//
//  Brain.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The package's entry point — the composition root that binds one brain home
// and hands out its domain surfaces. Storage flows from here by explicit
// injection; Paths and the Config/Genome caches are still process-global
// (see Session), so one live Brain per process until they move onto it.
public struct Brain {
    // MARK: - Property
    public let session: Session
    let container: Container

    public let index: Index
    public let query: Query
    public let consolidate: Consolidate
    public let genome: Genome
    public let ruleset: Ruleset
    public let operations: Operations

    // MARK: - Initializer
    public init(home: String) {
        let session = Session(home: home)
        let container = Container(storage: session.storage)

        self.session = session
        self.container = container
        self.index = Index(session: session, service: container.index)
        self.query = Query(
            retrieval: container.retrieval,
            notes: container.notes,
            stats: container.stats,
            lint: container.lint,
            enrichment: container.enrichment,
            consolidate: container.consolidate
        )
        self.consolidate = Consolidate(service: container.consolidate)
        self.genome = Genome(service: container.genome)
        self.ruleset = Ruleset(service: container.ruleset)
        self.operations = Operations(service: container.operations)
    }

    // MARK: - Public
    // MARK: - Private
}
