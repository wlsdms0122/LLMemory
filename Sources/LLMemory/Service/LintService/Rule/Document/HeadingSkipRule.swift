//
//  HeadingSkipRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct HeadingSkipRule: LintDocumentRule {
    // MARK: - Property
    let code = "heading-skip"
    let severity = LintSeverity.warn
    
    private let repeated = RepeatedFinding()
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ doc: LintDocument) -> [LintFinding] {
        var hits: [(from: Int, to: Int, path: String, line: Int)] = []
        var previousLevel: Int? = nil
        
        for section in doc.sections.sorted(by: { lhs, rhs in lhs.lineStart < rhs.lineStart }) {
            if let previousLevel, section.level > previousLevel + 1 {
                hits.append((previousLevel, section.level, section.path, section.lineStart + 1))
            }
            
            previousLevel = section.level
        }
        
        return repeated
            .groupBySubject(hits, by: { hit in "\(hit.from)→\(hit.to)\u{0}\(hit.path)" })
            .map { _, occurrences in
                let hit = occurrences[0]
                let lines = occurrences.map(\.line)
                
                return .init(
                    "heading level jump h\(hit.from)→h\(hit.to) (line \(lines[0]): '\(hit.path.prefix(60))')"
                        + repeated.repeatSuffix(lines),
                    key: "skip:h\(hit.from)-h\(hit.to):\(hit.path)"
                )
            }
    }
    
    // MARK: - Private
}
