//
//  FenceUnclosedRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct FenceUnclosedRule: LintDocumentRule {
    // MARK: - Property
    let code = "fence-unclosed"
    let severity = LintSeverity.error
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintDocument) -> [LintFinding] {
        guard let openLine = doc.unclosedFence else { return [] }
        
        return [
            .init("unclosed code fence (opened at line \(openLine + 1)) — the rest of the body is treated as fenced")
        ]
    }
    
    // MARK: - Private
}
