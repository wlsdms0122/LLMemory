//
//  OperationError.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// What an op throws when the world is not what validation found it to be.
//
// Every case here is a write-time discovery: validation already read the
// catalog and said yes, and between then and the write the file was gone, or
// the finding it was about had stopped being reported. The message is the
// whole value — it is what the caller is told, so it says which op and which
// subject rather than leaving a code to be looked up.
enum OperationError: Error, CustomStringConvertible {
    // A note the op is about has no file. The catalog said it exists.
    case noteFileMissing(String)
    // A note the op names is not in the catalog at all.
    case unknownNote(String)
    // A restore target is not in cortex/.trash/.
    case notInTrash(String)
    // A lint finding a keep-decision was about is no longer being reported.
    case findingVanished(String)
    // A `position` that validation let through and the write cannot read. It
    // carries the value, because the useful thing to say is what was given.
    case unreadablePosition(Any)
    
    // MARK: - Public
    var description: String {
        switch self {
        case .noteFileMissing(let detail):
            return detail
        
        case .unknownNote(let id):
            return "unknown id: \(id)"
        
        case .notInTrash(let id):
            return "not in trash: \(id)"
        
        case .findingVanished(let detail):
            return detail
        
        case .unreadablePosition(let position):
            return "position must be 'end'/'start' or {after|before: <path>}, got: \(position)"
        }
    }
}
