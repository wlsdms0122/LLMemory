//
//  ReconcileNoteEntitiesOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ReconcileNoteEntitiesOperation: GRDBOperation {
    // MARK: - Property
    let entities: [String]
    let noteId: String
    let now: Int

    // MARK: - Initializer
    init(entities: [String], noteId: String, now: Int) {
        self.entities = entities
        self.noteId = noteId
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        let want = entities.filter { entity in
            !entity.trimmingCharacters(in: .whitespaces).isEmpty
        }

        if want.isEmpty {
            try DeleteNoteEntitiesOperation(noteId: noteId).execute(db)

            return
        }

        let placeholders = want.map { _ in "?" }.joined(separator: ",")

        try db.execute(
            sql: "DELETE FROM entity_index WHERE note_id = ? AND entity NOT IN (\(placeholders))",
            arguments: StatementArguments([noteId] + want)
        )

        for entity in want {
            try db.execute(sql: """
                INSERT OR IGNORE INTO entity_index (entity, note_id, last_seen_at, hit_count)
                VALUES (?, ?, ?, 1)
                """, arguments: [entity, noteId, now])
        }
    }

    // MARK: - Private
}
