//
//  TouchNoteUsageOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct TouchNoteUsageOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, Int)
    let noteId: String
    let now: Int

    // MARK: - Initializer
    init(noteId: String, now: Int) {
        self.noteId = noteId
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO note_usage (note_id, hit_count, last_retrieved_at, created_at)
            VALUES (?, 0, ?, ?)
            ON CONFLICT(note_id) DO UPDATE SET last_retrieved_at = excluded.last_retrieved_at
            """, arguments: [noteId, now, now])
    }

    // MARK: - Private
}
