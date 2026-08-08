//
//  RulesetFeature.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import Storage

public struct RulesetFeature {
    public struct Summary {
        // MARK: - Property
        public let id: String
        public let name: String
        public let description: String?
        public let ruleCount: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct RuleView {
        // MARK: - Property
        public let id: Int64
        public let kind: String
        public let paramsJSON: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct ShowResult {
        // MARK: - Property
        public let id: String
        public let name: String
        public let description: String?
        public let rules: [RuleView]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public
    public func list() async throws -> [Summary] {
        try await session.storage.run(ListRulesetsTransaction())
    }

    public func show(id: String) async throws -> ShowResult? {
        try await session.storage.run(ShowRulesetTransaction(.init(id: id)))
    }

    public func effective(
        ruleset: String,
        axis: String
    ) async throws -> Ruleset.Effective? {
        try await session.storage.run(
            EffectiveRulesetTransaction(.init(ruleset: ruleset, axis: axis))
        )
    }

    // MARK: - Private
}
