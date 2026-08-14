//
//  BareHashLineRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct BareHashLineRule: LintDocumentRule {
    // MARK: - Property
    let code: String
    let severity: LintSeverity
    let pattern: LintLinePatternRule
    
    // MARK: - Initializer
    init() {
        code = "bare-hash-line"
        severity = .warn
        pattern = LintLinePatternRule(
            code: code,
            severity: severity,
            pattern: #"^#{1,6}[^#\s]"#
        ) { lineNumber, line in
            "no space after leading # (line \(lineNumber)): \(line.prefix(40)) — heading typo or unescaped channel name"
        }
    }
    
    // MARK: - Public
    func check(_ doc: LintDocument) -> [LintFinding] { pattern.check(doc) }
    
    // MARK: - Private
}
