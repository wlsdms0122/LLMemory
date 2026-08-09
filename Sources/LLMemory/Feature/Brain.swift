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

    public let index: Index
    public let query: Query
    public let consolidate: Consolidate
    public let genome: Genome
    public let ruleset: Ruleset
    public let operations: Operations

    // MARK: - Initializer
    public init(home: String) {
        let session = Session(home: home)

        self.session = session
        self.index = Index(session: session)
        self.query = Query(session: session)
        self.consolidate = Consolidate(session: session)
        self.genome = Genome(session: session)
        self.ruleset = Ruleset(session: session)
        self.operations = Operations(session: session)
    }

    // MARK: - Public
    // MARK: - Private
}
