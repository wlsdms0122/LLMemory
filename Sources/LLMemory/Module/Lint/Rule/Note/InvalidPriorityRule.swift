//
//  InvalidPriorityRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct InvalidPriorityRule: NoteLintRule {
    // MARK: - Property
    let code = "invalid-priority"
    let severity = LintSeverity.error
    
    private let valid: Set<String> = ["eager", "lazy"]
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        guard !valid.contains(note.doc.priority) else { return [] }
        
        return [.init("priority must be eager|lazy: '\(note.doc.priority)'")]
    }
    
    // MARK: - Private
}
