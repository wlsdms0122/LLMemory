//
//  ProjectNoteRefsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ProjectNoteRefsOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, [String], Int)
    let noteId: String
    let paths: [String]
    let now: Int

    private let sourceFingerprint = SourceFingerprint()

    // MARK: - Initializer
    init(noteId: String, paths: [String], now: Int) {
        self.noteId = noteId
        self.paths = paths
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        guard let fingerprint = sourceFingerprint.computeFingerprint(paths),
            let declHash = sourceFingerprint.computeDeclHash(paths)
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

        try RebaseNoteSourceOperation(
            noteId: noteId,
            paths: paths,
            now: now,
            fingerprint: fingerprint,
            declHash: declHash
        )
            .execute(db)
    }

    // MARK: - Private
}
