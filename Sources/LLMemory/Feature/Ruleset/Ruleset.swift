//
//  Ruleset.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Ruleset {
    // MARK: - Property
    let ruleset: RulesetService

    // MARK: - Initializer
    init(ruleset: RulesetService) {
        self.ruleset = ruleset
    }

    // MARK: - Public
    public func list() async throws -> [RulesetService.Summary] {
        try await ruleset.list()
    }

    public func show(id: String) async throws -> RulesetService.ShowResult? {
        try await ruleset.show(id: id)
    }

    public func effective(
        ruleset: String,
        axis: String
    ) async throws -> RulesetService.Effective? {
        try await self.ruleset.effective(ruleset: ruleset, axis: axis)
    }

    // MARK: - Private
}
