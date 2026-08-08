//
//  Brain.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// The package's entry point — the composition root that binds one brain home
// and hands out its domain surfaces. Pure DI: everything below receives its
// dependencies from here; nothing reads process-global storage.
public struct Brain {
    // MARK: - Property
    public let session: Session

    public let index: Index
    public let query: QueryFeature
    public let consolidate: Consolidate
    public let genome: GenomeFeature
    public let ruleset: RulesetFeature
    public let ops: Ops

    // MARK: - Initializer
    public init(home: String) {
        let session = Session(home: home)

        self.session = session
        self.index = Index(session: session)
        self.query = QueryFeature(session: session)
        self.consolidate = Consolidate(session: session)
        self.genome = GenomeFeature(session: session)
        self.ruleset = RulesetFeature(session: session)
        self.ops = Ops(session: session)
    }

    // MARK: - Public
    // MARK: - Private
}
