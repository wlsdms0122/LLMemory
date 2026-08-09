//
//  LintScanTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Runs the deterministic lint rule set — filtered, habituation-suppressed,
// and sorted for stable output.
struct LintScanTransaction: GRDBTransaction {
    // MARK: - Property
    let id: String?
    let code: String?
    let severity: String?
    let limit: Int?
    let includeDismissed: Bool

    // MARK: - Initializer
    init(
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) {
        self.id = id
        self.code = code
        self.severity = severity
        self.limit = limit
        self.includeDismissed = includeDismissed
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Lint.Issue] {
        var issues = try id != nil ? Lint.lintNote(db, nid: id!) : Lint.lintAll(db)

        if !includeDismissed {
            issues = try Lint.suppressDismissed(db, issues)
        }

        if let code { issues = issues.filter { issue in issue.code == code } }

        if let severity { issues = issues.filter { issue in issue.severity == severity } }

        issues.sort { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity == "error" }

            if lhs.target != rhs.target {
                if lhs.target.scope != rhs.target.scope {
                    return lhs.target.scope < rhs.target.scope
                }

                return lhs.target.subject < rhs.target.subject
            }

            if lhs.code != rhs.code { return lhs.code < rhs.code }

            return lhs.message < rhs.message
        }

        if let limit, issues.count > limit { issues = Array(issues.prefix(limit)) }

        return issues
    }

    // MARK: - Private
}
