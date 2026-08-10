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
    case pendingMigrations(brainRoot: String)
    case superseded(brainRoot: String)
    case schemaShapeMismatch(brainRoot: String, mismatches: [String])
    case lockFailed(errno: Int32)

    var description: String {
        switch self {
        case let .notInitialized(brainRoot):
            return "brain not initialized at \(brainRoot) — run 'llmemory init --home <path>' first"

        case let .dataDirMissing(path):
            return "data dir missing: \(path)"

        case let .pendingMigrations(brainRoot):
            return "brain schema at \(brainRoot) is behind this binary — "
                + "run 'llmemory update --home <path>' to migrate it forward "
                + "(back up first with `sqlite3 data/memory.db \".backup backup.db\"` — "
                + "WAL-safe, a plain file copy misses un-checkpointed -wal content)."

        case let .superseded(brainRoot):
            return "brain at \(brainRoot) was migrated by a newer llmemory binary — "
                + "this binary cannot read it safely. Upgrade the binary."

        case let .schemaShapeMismatch(brainRoot, mismatches):
            // A legacy v1 brain fails exactly here after the 2026-08 slimming —
            // recognise its retired shapes and point at the scripted path, which
            // carries the full semantic layer over instead of a lossy hand-copy.
            let legacyMarkers = ["ruleset", "rule", "note_meta",
                                 "file_mtime", "indexed_at", "source_checked_at"]
            let looksLegacy = mismatches.contains { message in
                legacyMarkers.contains { marker in message.contains(marker) }
            }
            let runbook = looksLegacy
                ? "This looks like a legacy v1 brain — run 'tool/migrate-legacy.sh <state-root>' "
                    + "(see document/MIGRATION.md); it backs up, rebuilds the canonical DB and "
                    + "carries the semantic layer over."
                : "Follow the schema-mismatch runbook: back up with `sqlite3 data/memory.db "
                    + "\".backup backup.db\"`, delete it, re-run 'init' + 'index build', then copy "
                    + "non-projection state back from the backup."

            return "brain schema shape mismatch at \(brainRoot) — migrations cannot reconcile it "
                + "(IF NOT EXISTS DDL never alters existing tables):\n"
                + mismatches.joined(separator: "\n") + "\n"
                + runbook
        
        case let .lockFailed(errorNumber):
            return "write lock failed: errno=\(errorNumber)"
        }
    }
}
