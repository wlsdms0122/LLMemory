//
//  TagAliasViolationRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct TagAliasViolationRule: NoteLintRule {
    // MARK: - Property
    let code = "tag-alias-violation"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        note.doc.tags.compactMap { tag in
            guard let canonical = index.tagAliases[tag] else { return nil }
            
            return .init(
                "frontmatter tag '\(tag)' is an old form canonicalized to '\(canonical)' — drift from an edit outside ops",
                key: "tag:\(tag)"
            )
        }
    }
    
    // MARK: - Private
}
