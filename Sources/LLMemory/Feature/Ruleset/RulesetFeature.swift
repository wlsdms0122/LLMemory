//
//  RulesetFeature.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import Storage

public enum RulesetFeature {
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
    // MARK: - Initializer
    // MARK: - Public
    public static func list(home: String) async throws -> [Summary] {
        Session.configure(home: home)

        return try await GRDBStorage.session.run(ListRulesetsTransaction())
    }

    public static func show(home: String, id: String) async throws -> ShowResult? {
        Session.configure(home: home)

        return try await GRDBStorage.session.run(ShowRulesetTransaction(.init(id: id)))
    }

    public static func effective(
        home: String,
        ruleset: String,
        axis: String
    ) async throws -> Ruleset.Effective? {
        Session.configure(home: home)

        return try await GRDBStorage.session.run(
            EffectiveRulesetTransaction(.init(ruleset: ruleset, axis: axis))
        )
    }

    // MARK: - Private
}
