//
//  EffectiveRulesetTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct EffectiveRulesetTransaction: GRDBTransaction {
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
        try connection.read { db -> Ruleset.Effective? in
            guard try Ruleset.rulesetExists(db, id: parameter.ruleset) else { return nil }

            return try Ruleset.effective(db, axis: parameter.axis, rulesetIds: [parameter.ruleset])
        }
    }
}

public extension EffectiveRulesetTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let ruleset: String
        public let axis: String

        // MARK: - Initializer
        public init(ruleset: String, axis: String) {
            self.ruleset = ruleset
            self.axis = axis
        }
    }

    typealias Result = Ruleset.Effective?
}
