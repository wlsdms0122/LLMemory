//
//  SummaryLongRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct SummaryLongRule: NoteLintRule {
    // MARK: - Property
    let code = "summary-long"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        guard note.doc.summary.count > 80 else { return [] }
        
        return [.init("summary \(note.doc.summary.count) chars (recommended ≤80)")]
    }
    
    // MARK: - Private
}
