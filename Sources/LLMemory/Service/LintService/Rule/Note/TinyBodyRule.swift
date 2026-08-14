//
//  TinyBodyRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct TinyBodyRule: NoteLintRule {
    // MARK: - Property
    let code = "tiny-body"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        let trimmed = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty, SectionEdit.wordCount(note.body) < 5 else { return [] }
        
        return [.init("body has fewer than 5 words")]
    }
    
    // MARK: - Private
}
