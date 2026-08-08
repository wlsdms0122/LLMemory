//
//  ListRulesetsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ListRulesetsTransaction: GRDBTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        try connection.read { db in
            try Ruleset.listRulesets(db).map { ruleset in
                let rules = try Ruleset.fetchRules(db, rulesetId: ruleset.id)

                return Ruleset.Summary(
                    id: ruleset.id,
                    name: ruleset.name,
                    description: ruleset.description,
                    ruleCount: rules.count
                )
            }
        }
    }
}

public extension ListRulesetsTransaction {
    typealias Parameter = Void
    typealias Result = [Ruleset.Summary]
}
