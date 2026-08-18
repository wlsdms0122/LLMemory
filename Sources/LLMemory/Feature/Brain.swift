//
//  Brain.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The package's entry point — the composition root that binds one brain home
// and hands out its domain surfaces. Everything flows from here by explicit
// injection: paths, configuration and genome values belong to the Session's
// context and reach an operation through the transaction that runs it, so two live
// brains in one process share nothing.
public struct Brain {
    // MARK: - Property
    public let session: Session
    let container: Container

    public let index: Index
    public let query: Query
    public let consolidate: Consolidate
    public let genome: Genome
    public let operations: Operations

    // MARK: - Initializer
    // Binding a home is async because opening the database is: whether that
    // means waiting is the driver's answer, and this one happens not to.
    public static func open(home: String) async throws -> Brain {
        Brain(session: try await Session.open(home: home))
    }

    private init(session: Session) {
        let container = Container(storage: session.store, brain: session.context)

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
        self.operations = Operations(service: container.operations)
    }

    // MARK: - Public
    // MARK: - Private
}
