//
//  ActivateNotesOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ActivateNotesOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = ([String], Int)
    let ids: [String]
    let now: Int

    // MARK: - Initializer
    init(ids: [String], now: Int) {
        self.ids = ids
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        guard !ids.isEmpty else { return }

        for noteId in ids {
            try db.execute(sql: """
                INSERT INTO note_usage (note_id, hit_count, last_retrieved_at, created_at)
                VALUES (?, 1, ?, ?)
                ON CONFLICT(note_id) DO UPDATE SET
                  hit_count = hit_count + 1,
                  last_retrieved_at = excluded.last_retrieved_at
                """, arguments: [noteId, now, now])
            try db.execute(sql: """
                UPDATE entity_index SET last_seen_at = ?, hit_count = hit_count + 1
                WHERE note_id = ?
                """, arguments: [now, noteId])
        }
    }

    // MARK: - Private
}
