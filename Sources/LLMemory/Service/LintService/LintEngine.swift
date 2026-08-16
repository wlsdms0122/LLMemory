//
//  LintEngine.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Runs document rules over one parsed note and stamps each finding with the
// rule that produced it. It knows nothing about which rules exist — the
// catalog is handed in, so a caller can drive one rule in isolation.
struct LintEngine {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func run(_ rules: [any LintDocumentRule], over document: LintDocument) -> [LintOutput] {
        rules.flatMap { rule in
            rule.check(document).map { finding in
                LintOutput(
                    severity: rule.severity,
                    code: rule.code,
                    message: finding.message,
                    target: finding.target ?? .note(document.id),
                    key: finding.key
                )
            }
        }
    }

    // MARK: - Private
}
