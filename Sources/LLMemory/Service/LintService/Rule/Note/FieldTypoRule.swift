//
//  FieldTypoRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// A field llmemory does not know is not a defect — that is what custom fields
// are. What is still a defect is a *near miss*: `summry:` parses fine, lands in
// extra, and leaves the real summary empty. Only edit-distance-1 neighbours of a
// first-class field are worth a word.
struct FieldTypoRule: NoteLintRule {
    // MARK: - Property
    let code = "field-typo"
    let severity = LintSeverity.warn
    
    private let distance = EditDistance()

    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        note.doc.extra.keys.sorted().compactMap { field in
            guard let known = Frontmatter.knownFields.first(
                where: { known in distance.withinOne(field, known) }
            ) else {
                return nil
            }
            
            return .init(
                "custom field '\(field)' is one edit from '\(known)' — typo, or meant as its own field?",
                key: "field:\(field)"
            )
        }
    }
    
    // MARK: - Private
}
