//
//  RulesetService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Ruleset-domain service — mutation-policy observation surfaces.
public enum RulesetService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func list(_ storage: GRDBStorage) async throws -> [Ruleset.Summary] {
        try await storage.run(ListRulesetsTransaction())
    }

    public static func show(_ storage: GRDBStorage, id: String) async throws -> Ruleset.ShowResult? {
        try await storage.run(ShowRulesetTransaction(.init(id: id)))
    }

    public static func effective(
        _ storage: GRDBStorage,
        ruleset: String,
        axis: String
    ) async throws -> Ruleset.Effective? {
        try await storage.run(EffectiveRulesetTransaction(.init(ruleset: ruleset, axis: axis)))
    }

    // MARK: - Private
}
