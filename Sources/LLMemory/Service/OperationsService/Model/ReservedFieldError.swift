//
//  ReservedFieldError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// A field that exists but is not this op's to set. Each has an op of its own,
// and the message says which — the whole point of refusing rather than merging.
struct ReservedFieldError: Error, CustomStringConvertible {
    // MARK: - Property
    let field: String
    
    var description: String {
        let owner: String
        
        switch field {
        case "id":
            owner = "migrate_note moves it"
        
        case "stale", "invalidated_at", "invalidated_reason":
            owner = "invalidate/revalidate own it"
        
        case "trashed_at", "trashed_reason":
            owner = "delete_note/restore_note own it"
        
        default:
            owner = "it is edited in the file only"
        }
        
        return "reserved field '\(field)' — \(owner)"
    }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
