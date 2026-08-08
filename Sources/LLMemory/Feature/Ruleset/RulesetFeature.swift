//
//  RulesetFeature.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

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
    public static func list(home: String) throws -> [Summary] {
        let queue = try prepare(home)
        
        return try queue.read { db in
            try Ruleset.listRulesets(db).map { ruleset in
                let rules = try Ruleset.fetchRules(db, rulesetId: ruleset.id)
                
                return Summary(
                    id: ruleset.id,
                    name: ruleset.name,
                    description: ruleset.description,
                    ruleCount: rules.count
                )
            }
        }
    }
    
    public static func show(home: String, id: String) throws -> ShowResult? {
        let queue = try prepare(home)
        
        return try queue.read { db -> ShowResult? in
            guard let ruleset = try Ruleset.getRuleset(db, id: id) else { return nil }
            
            let rules = try Ruleset.fetchRules(db, rulesetId: id).map { rule in
                RuleView(id: rule.id, kind: rule.kind, paramsJSON: rule.paramsRaw)
            }
            
            return ShowResult(
                id: ruleset.id,
                name: ruleset.name,
                description: ruleset.description,
                rules: rules
            )
        }
    }
    
    public static func effective(
        home: String,
        ruleset: String,
        axis: String
    ) throws -> Ruleset.Effective? {
        let queue = try prepare(home)
        
        return try queue.read { db -> Ruleset.Effective? in
            guard try Ruleset.rulesetExists(db, id: ruleset) else { return nil }
            
            return try Ruleset.effective(db, axis: axis, rulesetIds: [ruleset])
        }
    }
    
    // MARK: - Private
    private static func prepare(_ home: String) throws -> any DatabaseWriter {
        Session.configure(home: home)
        
        return try GRDBStorage.session.connect()
    }
}
