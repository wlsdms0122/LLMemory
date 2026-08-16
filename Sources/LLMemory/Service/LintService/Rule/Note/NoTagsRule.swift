//
//  NoTagsRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct NoTagsRule: NoteLintRule {
    // MARK: - Property
    let code = "no-tags"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        note.doc.tags.isEmpty ? [.init("tags is empty")] : []
    }
    
    // MARK: - Private
}
