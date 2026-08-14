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
// the finding it was about had stopped being reported.
//
// A case carries its subject and nothing else; `description` writes the
// sentence. The alternative — letting each throw site pass a finished sentence
// — is how ten call sites end up phrasing the same event ten ways, and how a
// later case gets added with whichever convention its author happened to read.
enum OperationError: Error, CustomStringConvertible {
    // A note the op is about has no file, though the catalog says it exists.
    case noteFileMissing(op: String, id: String)
    // A note the op names is not in the catalog at all.
    case unknownNote(String)
    // A restore target is not in cortex/.trash/.
    case notInTrash(String)
    // A lint finding a keep-decision was about is no longer being reported.
    case findingVanished(code: String, subject: String)
    // A `position` that validation let through and the write cannot read. It
    // carries the value as text, because saying what was given is the only
    // thing done with it — and `Any` would cost the type its Sendable.
    case unreadablePosition(String)
    // A file the transaction wanted to snapshot could not be read, so there is
    // nothing to put back if the batch fails.
    case snapshotUnreadable(path: String, reason: String)

    // MARK: - Public
    var description: String {
        switch self {
        case .noteFileMissing(let op, let id):
            return "\(op): note file missing: \(id)"

        case .unknownNote(let id):
            return "unknown id: \(id)"

        case .notInTrash(let id):
            return "not in trash: \(id)"

        case .findingVanished(let code, let subject):
            return "dismiss_candidate: '\(code)' finding on \(subject) is no longer present at write "
                + "time — another op in this batch changed the note; dismiss it in a separate call"

        case .unreadablePosition(let position):
            return "position must be 'end'/'start' or {after|before: <path>}, got: \(position)"

        case .snapshotUnreadable(let path, let reason):
            return "snapshot read failed: \(path): \(reason)"
        }
    }
}
