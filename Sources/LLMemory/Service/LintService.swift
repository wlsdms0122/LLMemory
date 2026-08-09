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
            try scan(
                scope,
                id: id,
                code: code,
                severity: severity,
                limit: limit,
                includeDismissed: includeDismissed
            )
        }
    }

    // MARK: - Internal
    // The inspector core — runs the rule catalog, suppresses habituated
    // findings, and sorts for stable output. What counts as a defect is
    // decided here (and in Lint/LintRules); the DB module only fetches.
    func scan(
        _ scope: GRDBReadScope,
        id: String? = nil,
        code: String? = nil,
        severity: String? = nil,
        limit: Int? = nil,
        includeDismissed: Bool = false
    ) throws -> [Lint.Issue] {
        var issues = try id != nil
            ? Lint.lintNote(scope, nid: id!)
            : Lint.lintAll(scope)

        if !includeDismissed {
            issues = try Lint.suppressDismissed(scope, issues)
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
