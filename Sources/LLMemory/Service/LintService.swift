//
//  LintService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Lint-domain service — deterministic observation of corpus shape, with
// habituation suppressing findings the owner has reviewed and kept.
public struct LintService: Sendable {
    // MARK: - Property
    let storage: GRDBStorage

    // MARK: - Initializer
    init(storage: GRDBStorage) {
        self.storage = storage
    }

    // MARK: - Public
    public func lint(
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) async throws -> [Lint.Issue] {
        try await storage.read { scope in
            try scope.run(
                LintScanTransaction(
                    id: id,
                    code: code,
                    severity: severity,
                    limit: limit,
                    includeDismissed: includeDismissed
                )
            )
        }
    }

    // MARK: - Private
}
