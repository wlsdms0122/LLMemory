//
//  FetchNoteHistoryTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteHistoryTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String
    let limit: Int

    // MARK: - Initializer
    init(noteId: String, limit: Int) {
        self.noteId = noteId
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [NoteHistoryEvent] {
        try Row.fetchAll(db, sql: """
            SELECT kind, reason, created_at FROM note_lifecycle_events
            WHERE note_id = ? ORDER BY id DESC LIMIT ?
            """, arguments: [noteId, limit])
            .map { row in
                NoteHistoryEvent(
                    kind: row["kind"],
                    reason: row["reason"] as String?,
                    at: row["created_at"]
                )
            }
    }

    // MARK: - Private
}
