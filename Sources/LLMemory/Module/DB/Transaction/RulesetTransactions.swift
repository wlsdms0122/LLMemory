//
//  RulesetTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Ruleset-domain transactions — row access for mutation-policy rulesets;
// rule interpretation (params typing, folding) is RulesetService's.
struct FetchRulesetsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [RulesetRecord] {
        try RulesetRecord.order(Column("id")).fetchAll(db)
    }

    // MARK: - Private
}

struct FetchRulesetTransaction: GRDBReadTransaction {
    // MARK: - Property
    let id: String

    // MARK: - Initializer
    init(id: String) {
        self.id = id
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> RulesetRecord? {
        try RulesetRecord.fetchOne(db, key: id)
    }

    // MARK: - Private
}

struct RulesetExistsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let id: String

    // MARK: - Initializer
    init(id: String) {
        self.id = id
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try RulesetRecord.exists(db, key: id)
    }

    // MARK: - Private
}

struct FetchRulesTransaction: GRDBReadTransaction {
    // MARK: - Property
    let rulesetId: String

    // MARK: - Initializer
    init(rulesetId: String) {
        self.rulesetId = rulesetId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [RuleRecord] {
        try RuleRecord
            .filter(Column("ruleset_id") == rulesetId && Column("enabled") == true)
            .order(Column("id"))
            .fetchAll(db)
    }

    // MARK: - Private
}
