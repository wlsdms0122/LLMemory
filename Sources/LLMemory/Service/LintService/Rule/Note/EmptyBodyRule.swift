//
//  EmptyBodyRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct EmptyBodyRule: NoteLintRule {
    // MARK: - Property
    let code = "empty-body"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [.init("body is empty")]
            : []
    }
    
    // MARK: - Private
}
