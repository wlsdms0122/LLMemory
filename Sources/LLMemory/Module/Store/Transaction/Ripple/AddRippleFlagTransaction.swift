//
//  AddRippleFlagTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct AddRippleFlagTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let kind: String
    let reason: String
    let now: Int

    // MARK: - Initializer
    init(noteId: String, kind: String, reason: String, now: Int) {
        self.noteId = noteId
        self.kind = kind
        self.reason = reason
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let reason = self.reason.unicodeScalarPrefix(200)
        let stateRow = try Row.fetchOne(db, sql: """
            SELECT (resolved_at IS NOT NULL) AS resolved
            FROM ripple_flags WHERE note_id = ? AND flag = ?
            """, arguments: [noteId, kind])
        let isReoccurrence: Bool

        if let stateRow {
            isReoccurrence = (stateRow["resolved"] as Int? ?? 0) == 1
        } else {
            isReoccurrence = false
        }

        let isNew = stateRow == nil

        try db.execute(sql: """
            INSERT INTO ripple_flags (note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at)
            VALUES (?, ?, ?, ?, ?, 1, NULL)
            ON CONFLICT(note_id, flag) DO UPDATE SET
              reason = excluded.reason,
              last_flagged_at = excluded.last_flagged_at,
              flag_count = ripple_flags.flag_count + 1,
              resolved_at = NULL
            """, arguments: [noteId, kind, reason, now, now])

        if isNew || isReoccurrence {
            try db.execute(sql: """
                INSERT INTO note_lifecycle_events (note_id, kind, reason, created_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [noteId, "flagged", "\(kind): \(reason)", now])
        }
    }

    // MARK: - Private
}
