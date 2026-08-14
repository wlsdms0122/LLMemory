//
//  SectionError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

enum SectionError: Error, CustomStringConvertible {
    case parse(String)
    case notFound(String)
    case ambiguous(String)
    case guarded(String)
    case invariant([SectionEdit.PathCollision], noteId: String)
    
    var description: String {
        switch self {
        case .parse(let message), .notFound(let message), .ambiguous(let message),
            .guarded(let message):
            return message
        
        case .invariant(let collisions, let noteId):
            let details = collisions.map { collision in collision.display() }
                .joined(separator: "; ")
            let prefix = noteId.isEmpty ? "" : "note \(noteId): "
            
            return "\(prefix)section path collision: \(details)"
        }
    }
}
