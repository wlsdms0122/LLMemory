//
//  EmptySectionRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct EmptySectionRule: LintDocumentRule {
    // MARK: - Property
    let code = "empty-section"
    let severity = LintSeverity.warn
    
    private let repeated = RepeatedFinding()

    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintDocument) -> [LintFinding] {
        let hits = doc.sections.filter { section in
            let inner = doc.lines[(section.lineStart + 1)..<section.lineEnd]
            
            return !inner.contains(where: { line in
                !line.trimmingCharacters(in: .whitespaces).isEmpty
            })
        }
        
        return repeated.groupBySubject(hits, by: \.path).map { _, sections in
            let section = sections[0]
            let lines = sections.map { section in section.lineStart + 1 }
            
            return .init(
                "empty section: \(section.path) (line \(lines[0]))"
                    + repeated.repeatSuffix(lines),
                key: "empty:\(section.path)"
            )
        }
    }
    
    // MARK: - Private
}
