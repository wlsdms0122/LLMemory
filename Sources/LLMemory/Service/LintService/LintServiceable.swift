//
//  LintServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The lint domain as a caller with no scope of its own sees it: ask what may
// be reported, and ask what is being reported.
protocol LintServiceable: Sendable {
    func lint(
        id: String?,
        code: String?,
        severity: String?,
        limit: Int?,
        includeDismissed: Bool
    ) async throws -> [LintIssue]
    
    func ruleCatalog() -> [LintRuleInfo]
}
