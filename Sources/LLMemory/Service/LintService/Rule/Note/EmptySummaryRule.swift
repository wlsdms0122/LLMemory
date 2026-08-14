//
//  EmptySummaryRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct EmptySummaryRule: NoteLintRule {
    // MARK: - Property
    let code = "empty-summary"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        note.doc.summary.isEmpty ? [.init("summary is empty")] : []
    }
    
    // MARK: - Private
}
