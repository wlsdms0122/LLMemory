//
//  AdjacentEmptyHeadingRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct AdjacentEmptyHeadingRule: LintDocumentRule {
    // MARK: - Property
    let code = "adjacent-empty-heading"
    let severity = LintSeverity.warn
    
    private let engine = LintEngine()

    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintDocument) -> [LintFinding] {
        let hits = doc.sections.filter { section in section.lineEnd == section.lineStart + 1 }
        
        return engine.groupBySubject(hits, by: \.path).map { _, sections in
            let section = sections[0]
            let lines = sections.map { section in section.lineStart + 1 }
            
            return .init(
                "heading immediately followed by another heading: \(section.path) (line \(lines[0])) — likely lost or displaced body"
                    + engine.repeatSuffix(lines),
                key: "adjacent:\(section.path)"
            )
        }
    }
    
    // MARK: - Private
}
