//
//  InvalidIDRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct InvalidIDRule: NoteLintRule {
    // MARK: - Property
    let code = "invalid-id"
    let severity = LintSeverity.error
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        let nsId = note.nid as NSString
        
        guard NoteAddress.idRegex.firstMatch(
            in: note.nid,
            range: NSRange(location: 0, length: nsId.length)
        ) == nil else {
            return []
        }
        
        return [.init("id must be dot-joined kebab-case labels: '\(note.nid)'")]
    }
    
    // MARK: - Private
}
