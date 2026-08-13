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

struct NoteUnreadable: Error, CustomStringConvertible {
    // MARK: - Property
    let path: String
    let reason: String
    
    var description: String { "unreadable note file \(path): \(reason)" }
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

enum NotesError: Error, CustomStringConvertible {
    case invalidPriority(String)
    case notUnderBrainRoot(String)
    case notALiveNote(path: String, reason: String)
    case unknownIds([String])
    case trashUnreadable(nid: String, files: [String], matched: Bool)
    case stampedFileVanished(nid: String, path: String)
    case noteFileMissing(path: String)
    
    var description: String {
        switch self {

        
        case .invalidPriority(let priority):
            return "invalid priority: \(priority)"
        
        case .notUnderBrainRoot(let path):
            return "file not under BRAIN_ROOT: \(path)"
        
        case .notALiveNote(let path, let reason):
            return "not a live note: \(path) — \(reason)"
        
        case .unknownIds(let ids):
            return "unknown id: \(ids.joined(separator: ", "))"
        
        case .noteFileMissing(let path):
            return "note file does not exist: \(path)"
        
        case .stampedFileVanished(let nid, let path):
            return "note file vanished between write and stamp: \(nid) → \(path)"
        
        case .trashUnreadable(let nid, let files, let matched):
            let why = matched
                ? "a readable incarnation of '\(nid)' was found, but an unreadable trash file may be a "
                    + "later one — restoring the readable one would quietly bring back an older version"
                : "one of them may be '\(nid)' itself, so 'not in trash' would be a guess"
            
            return "cannot resolve '\(nid)' in trash — \(files.count) trash file(s) unreadable; "
                + why + ": \(files.joined(separator: "; "))"
        }
    }
}
