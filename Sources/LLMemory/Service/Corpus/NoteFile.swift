//
//  NoteFile.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import CryptoKit

// File-level note mechanics — parsing, hashing, path mapping. Row and FTS
// projections are note transactions.
struct NoteFile: Sendable {
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
    
    private let frontmatter = Frontmatter()

    // MARK: - Initializer
    // MARK: - Public
    func contentHash(_ text: String) -> String {
        let digest = SHA256.hash(data: text.data(using: .utf8) ?? Data())
        
        return String(digest.map { byte in String(format: "%02x", byte) }.joined().prefix(16))
    }
    
    func requireNote(at url: URL) throws -> (doc: FrontmatterDocument, body: String) {
        guard let read = try readNoteIfPresent(at: url) else {
            throw NoteUnreadable(path: url.path, reason: "file does not exist")
        }
        
        return read
    }
    
    func readNoteIfPresent(at url: URL) throws -> (doc: FrontmatterDocument, body: String)? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            return try frontmatter.parse(try String(contentsOf: url, encoding: .utf8))
        } catch {
            throw NoteUnreadable(path: url.path, reason: "\(error)")
        }
    }
    
    // MARK: - Private
}
