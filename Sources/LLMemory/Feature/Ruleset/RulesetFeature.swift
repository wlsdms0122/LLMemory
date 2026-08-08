//
//  RulesetFeature.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct RulesetFeature {
    // MARK: - Property
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public
    public func list() async throws -> [Ruleset.Summary] {
        try await RulesetService.list(session.storage)
    }

    public func show(id: String) async throws -> Ruleset.ShowResult? {
        try await RulesetService.show(session.storage, id: id)
    }

    public func effective(
        ruleset: String,
        axis: String
    ) async throws -> Ruleset.Effective? {
        try await RulesetService.effective(session.storage, ruleset: ruleset, axis: axis)
    }

    // MARK: - Private
}
