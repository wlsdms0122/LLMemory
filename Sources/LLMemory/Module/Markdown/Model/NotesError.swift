//
//  NotesError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import CryptoKit

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
