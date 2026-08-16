//
//  NoteSourceInput.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The `source` field's own grammar. A source is a list of refs, given as one
// string or many; the two members here are the same rule read twice — once to
// refuse bad input, once to normalise good input.
struct NoteSourceInput {
    // MARK: - Property
    private let frontmatter = Frontmatter()
    
    // MARK: - Initializer
    // MARK: - Public
    func finalizeSource(_ items: Any?) throws -> [String] {
        guard let items else { return [] }
        
        return try frontmatter.decodeSource(items)
    }
    
    func sourceInputError(_ items: Any?) -> String? {
        guard let items else { return nil }
        
        do {
            _ = try frontmatter.decodeSource(items)
            
            return nil
        } catch {
            return "\(error)"
        }
    }
    
    // MARK: - Private
}
