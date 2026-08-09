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
    let services: Services

    public let index: Index
    public let query: Query
    public let consolidate: Consolidate
    public let genome: Genome
    public let ruleset: Ruleset
    public let operations: Operations

    // MARK: - Initializer
    public init(home: String) {
        let session = Session(home: home)
        let services = Services(storage: session.storage)

        self.session = session
        self.services = services
        self.index = Index(session: session, index: services.index)
        self.query = Query(
            retrieval: services.retrieval,
            notes: services.notes,
            stats: services.stats,
            lint: services.lint,
            enrichment: services.enrichment,
            consolidate: services.consolidate
        )
        self.consolidate = Consolidate(consolidate: services.consolidate)
        self.genome = Genome(genome: services.genome)
        self.ruleset = Ruleset(ruleset: services.ruleset)
        self.operations = Operations(operations: services.operations)
    }

    // MARK: - Public
    // MARK: - Private
}
