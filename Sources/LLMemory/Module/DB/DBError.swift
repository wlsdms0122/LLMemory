//
//  DBError.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation

enum DBError: Error, CustomStringConvertible {
    case notInitialized(String)
    case dataDirMissing(String)
    case schemaVersionMismatch(brainRoot: String, db: Int, code: Int)
    case schemaShapeMismatch(brainRoot: String, mismatches: [String])
    case lockFailed(errno: Int32)
    
    var description: String {
        switch self {
        case let .notInitialized(brainRoot):
            return "brain not initialized at \(brainRoot) — run 'llmemory init --home <path>' first"
        
        case let .dataDirMissing(path):
            return "data dir missing: \(path)"
        
        case let .schemaVersionMismatch(brainRoot, dbVersion, codeVersion):
            return "brain schema version mismatch at \(brainRoot): db=\(dbVersion), code expects=\(codeVersion). "
                + "Back up first with `sqlite3 data/memory.db \".backup backup.db\"` (WAL-safe — "
                + "a plain file copy misses un-checkpointed -wal content), then delete it and "
                + "re-run 'init' + 'index build' — "
                + "cortex/ markdown re-derives the projection, but non-projection brain state "
                + "(note_usage/note_links/note_retrieval_terms/events …) only survives if you "
                + "copy it back from the backup (sqlite3 ATTACH + INSERT … JOIN notes)."
        
        case let .schemaShapeMismatch(brainRoot, mismatches):
            return "brain schema shape mismatch at \(brainRoot) — init cannot reconcile it "
                + "(IF NOT EXISTS DDL never alters existing tables), so the version stamp "
                + "was withheld and nothing was changed:\n"
                + mismatches.joined(separator: "\n") + "\n"
                + "Follow the schema-mismatch runbook: back up with `sqlite3 data/memory.db "
                + "\".backup backup.db\"`, delete it, re-run 'init' + 'index build', then copy "
                + "non-projection state back from the backup."
        
        case let .lockFailed(errorNumber):
            return "write lock failed: errno=\(errorNumber)"
        }
    }
}
