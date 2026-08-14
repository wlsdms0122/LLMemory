//
//  AddressInFrontmatterRule.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// An `id:` line is ignored by the parser, which is exactly why it needs saying:
// a note that writes an address in its text while living at another one reads as
// authoritative and is not. Nothing breaks — the note is simply lying quietly.
struct AddressInFrontmatterRule: NoteLintRule {
    // MARK: - Property
    let code = "address-in-frontmatter"
    let severity = LintSeverity.warn
    
    // MARK: - Initializer
    // MARK: - Public
    func check(_ note: NoteLintInput, _ index: LintCorpusIndex) -> [LintFinding] {
        guard let declared = note.declaredId else { return [] }
        
        return [.init(
            "frontmatter declares 'id: \(declared)' — the address is where the file is "
                + "(\(note.nid)), so remove the line"
        )]
    }
    
    // MARK: - Private
}
