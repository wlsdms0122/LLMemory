//
//  UpsertPendingTermOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct UpsertPendingTermOperation: GRDBOperation {
    // MARK: - Property
    let noteId: String
    let kind: String
    let term: String
    let provenance: String?
    let now: Int

    // MARK: - Initializer
    init(noteId: String, kind: String, term: String, provenance: String?, now: Int) {
        self.noteId = noteId
        self.kind = kind
        self.term = term
        self.provenance = provenance
        self.now = now
    }

    // MARK: - Public
    // Inserts pending or revives a rejected row; returns the change count so
    // the handler can report how many landed.
    @discardableResult
    func execute(_ db: Database) throws -> Int {
        try db.execute(sql: """
            INSERT INTO note_retrieval_terms
              (note_id, kind, term, status, provenance, created_at)
            VALUES (?, ?, ?, 'pending', ?, ?)
            ON CONFLICT(note_id, kind, term) DO UPDATE SET
              status = 'pending',
              provenance = excluded.provenance,
              reject_reason = NULL,
              validated_at = NULL,
              created_at = excluded.created_at
            WHERE note_retrieval_terms.status = 'rejected'
            """, arguments: [noteId, kind, term, provenance, now])

        return db.changesCount
    }

    // MARK: - Private
}
