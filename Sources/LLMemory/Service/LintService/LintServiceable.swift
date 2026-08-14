//
//  LintServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The inspector surface — runs the rule catalog over the corpus and reports
// what looks like a defect, minus whatever a person has reviewed and kept.
//
// `scan` and the two code sets are on the contract because the
// dismiss_candidate handler calls them from inside its own write scope: it
// has to see the live findings before it may record a keep-decision against
// one, and it has to know which codes are answerable at all.
protocol LintServiceable: Sendable {
    var dismissibleCodes: Set<String> { get }
    var errorCodes: Set<String> { get }

    func lint(
        id: String?,
        code: String?,
        severity: String?,
        limit: Int?,
        includeDismissed: Bool
    ) async throws -> [LintIssue]

    func ruleCatalog() -> [LintRuleInfo]

    func scan(
        _ scope: GRDBReadScope,
        id: String?,
        code: String?,
        severity: String?,
        limit: Int?,
        includeDismissed: Bool
    ) throws -> [LintIssue]
}
