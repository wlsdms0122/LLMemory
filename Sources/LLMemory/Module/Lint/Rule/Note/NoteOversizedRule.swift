//
//  NoteOversizedRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct NoteOversizedRule: NoteLintRule {
    // MARK: - Property
    let code = "note-oversized"
    let severity = LintSeverity.warn
    
    private let sectionEdit = SectionEdit()
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        guard note.doc.template == nil, !note.doc.locked else { return [] }
        
        let threshold = index.oversizedWords
        let words = sectionEdit.wordCount(note.body)
        
        guard words >= threshold else { return [] }
        
        let sections = sectionEdit.sectionCount(note.body)
        
        return [
            .init(
                "\(words) words in \(sections) sections — one retrieval loads all of it; "
                    + "inspect shape with `query get \(note.nid) --toc`, read parts with --section"
            )
        ]
    }
    
    // MARK: - Private
}
