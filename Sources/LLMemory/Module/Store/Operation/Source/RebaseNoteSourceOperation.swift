//
//  RebaseNoteSourceOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RebaseNoteSourceOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, [String], Int, String?, String?)
    let noteId: String
    let paths: [String]
    let now: Int
    let fingerprint: String?
    let declHash: String?

    private let sourceFingerprint = SourceFingerprint()

    // MARK: - Initializer
    init(
        noteId: String,
        paths: [String],
        now: Int,
        fingerprint: String? = nil,
        declHash: String? = nil
    ) {
        self.noteId = noteId
        self.paths = paths
        self.now = now
        self.fingerprint = fingerprint
        self.declHash = declHash
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        guard let fingerprint = fingerprint ?? sourceFingerprint.computeFingerprint(paths),
            let declHash = declHash ?? sourceFingerprint.computeDeclHash(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )

            return
        }

        try db.execute(sql: """
            INSERT INTO note_source (note_id, source_hash, source_stale, decl_hash)
            VALUES (?, ?, 0, ?)
            ON CONFLICT(note_id) DO UPDATE SET
              source_hash = excluded.source_hash,
              source_stale = 0, decl_hash = excluded.decl_hash
            """, arguments: [noteId, fingerprint, declHash])
    }

    // MARK: - Private
}
