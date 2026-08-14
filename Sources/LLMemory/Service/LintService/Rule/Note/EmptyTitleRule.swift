//
//  EmptyTitleRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct EmptyTitleRule: NoteLintRule {
    // MARK: - Property
    let code = "empty-title"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        note.doc.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [.init("title is empty")]
            : []
    }
    
    // MARK: - Private
}
