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
    // MARK: - Property
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public
    public func list() async throws -> [Ruleset.Summary] {
        try await session.storage.run(ListRulesetsTransaction())
    }

    public func show(id: String) async throws -> Ruleset.ShowResult? {
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
