//
//  Ruleset.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Ruleset {
    // MARK: - Property
    let service: RulesetService

    // MARK: - Initializer
    init(service: RulesetService) {
        self.service = service
    }

    // MARK: - Public
    public func list() async throws -> [RulesetService.Summary] {
        try await service.list()
    }

    public func show(id: String) async throws -> RulesetService.ShowResult? {
        try await service.show(id: id)
    }

    public func effective(
        ruleset: String,
        axis: String
    ) async throws -> RulesetService.Effective? {
        try await service.effective(ruleset: ruleset, axis: axis)
    }

    // MARK: - Private
}
