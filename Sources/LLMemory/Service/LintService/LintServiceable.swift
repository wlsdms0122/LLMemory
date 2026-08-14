//
//  LintServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The inspector surface — runs the rule catalog over the corpus and reports
// what looks like a defect, minus whatever a person has reviewed and kept.
protocol LintServiceable: Sendable {
    func lint(
        id: String?,
        code: String?,
        severity: String?,
        limit: Int?,
        includeDismissed: Bool
    ) async throws -> [Lint.Issue]
}
