//
//  ProjectNoteRefsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ProjectNoteRefsTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let paths: [String]
    let now: Int

    // MARK: - Initializer
    init(noteId: String, paths: [String], now: Int) {
        self.noteId = noteId
        self.paths = paths
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard let fingerprint = SourceFingerprint.computeFingerprint(paths),
            let declHash = SourceFingerprint.computeDeclHash(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )

            return
        }

        let stored = try String.fetchOne(
            db,
            sql: "SELECT decl_hash FROM note_source WHERE note_id = ?",
            arguments: [noteId]
        )

        if stored == declHash { return }

        try RebaseNoteSourceTransaction(
            noteId: noteId,
            paths: paths,
            now: now,
            fingerprint: fingerprint,
            declHash: declHash
        )
            .perform(db)
    }

    // MARK: - Private
}
