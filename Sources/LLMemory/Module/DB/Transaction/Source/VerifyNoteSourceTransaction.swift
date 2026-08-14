//
//  VerifyNoteSourceTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct VerifyNoteSourceTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let now: Int?

    // MARK: - Initializer
    init(noteId: String, now: Int? = nil) {
        self.noteId = noteId
        self.now = now
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> Bool {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)
        let row = try Row.fetchOne(
            db,
            sql: "SELECT source_hash, decl_hash FROM note_source WHERE note_id = ?",
            arguments: [noteId]
        )

        guard let row, let stored = row["source_hash"] as String?, !stored.isEmpty else {
            return false
        }

        let paths = try FetchNoteSourcePathsTransaction(noteId: noteId).perform(db)

        guard let currentDecl = SourceFingerprint.computeDeclHash(paths),
            let current = SourceFingerprint.computeFingerprint(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )

            return false
        }

        if currentDecl != (row["decl_hash"] as String?) {
            try RebaseNoteSourceTransaction(
                noteId: noteId,
                paths: paths,
                now: timestamp,
                fingerprint: current,
                declHash: currentDecl
            )
                .perform(db)

            return false
        }

        let stale = current != stored

        try db.execute(
            sql: "UPDATE note_source SET source_stale = ? WHERE note_id = ?",
            arguments: [stale ? 1 : 0, noteId]
        )

        return stale
    }

    // MARK: - Private
}
