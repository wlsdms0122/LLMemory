//
//  ShowRulesetTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ShowRulesetTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        try connection.read { db -> RulesetFeature.ShowResult? in
            guard let ruleset = try Ruleset.getRuleset(db, id: parameter.id) else { return nil }

            let rules = try Ruleset.fetchRules(db, rulesetId: parameter.id).map { rule in
                RulesetFeature.RuleView(id: rule.id, kind: rule.kind, paramsJSON: rule.paramsRaw)
            }

            return RulesetFeature.ShowResult(
                id: ruleset.id,
                name: ruleset.name,
                description: ruleset.description,
                rules: rules
            )
        }
    }
}

public extension ShowRulesetTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let id: String

        // MARK: - Initializer
        public init(id: String) {
            self.id = id
        }
    }

    typealias Result = RulesetFeature.ShowResult?
}
