//
//  Notes.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import CryptoKit

// File-level note mechanics — parsing, hashing, path mapping. Row and FTS
// projections are note transactions.
enum Notes {
    // MARK: - Property
    // Markers carry dots now that an id does. Widening only adds marker rows —
    // an edge still needs an exact match against a real id, so a config key
    // like `priming.alpha` reaching the table costs nothing and links nothing.
    static let wikilinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([a-z0-9][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)*)\]\]"#
    )
    static let backtickIdRegex = try! NSRegularExpression(
        pattern: #"`([a-z][a-z0-9-]{2,}(?:\.[a-z0-9][a-z0-9-]*)*)`"#
    )
    
    // MARK: - Initializer
    // MARK: - Public
    static func contentHash(_ text: String) -> String {
        let digest = SHA256.hash(data: text.data(using: .utf8) ?? Data())
        
        return String(digest.map { byte in String(format: "%02x", byte) }.joined().prefix(16))
    }
    
    static func requireNote(at url: URL) throws -> (doc: FrontmatterDoc, body: String) {
        guard let read = try readNoteIfPresent(at: url) else {
            throw NoteUnreadable(path: url.path, reason: "file does not exist")
        }
        
        return read
    }
    
    static func readNoteIfPresent(at url: URL) throws -> (doc: FrontmatterDoc, body: String)? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            return try Frontmatter.parse(try String(contentsOf: url, encoding: .utf8))
        } catch {
            throw NoteUnreadable(path: url.path, reason: "\(error)")
        }
    }
    
    static func relativeToBrainRoot(_ file: URL) throws -> String {
        guard let relativePath = Paths.relative(of: file) else {
            throw NotesError.notUnderBrainRoot(file.path)
        }
        
        return relativePath
    }
    
    // MARK: - Private
}
