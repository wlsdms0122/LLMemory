//
//  FetchNoteEntityHitsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteEntityHitsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(entity: String, hits: Int)] {
        try Row.fetchAll(
            db,
            sql: "SELECT entity, hit_count FROM entity_index WHERE note_id = ?",
            arguments: [noteId]
        )
            .map { row in (entity: row["entity"], hits: row["hit_count"]) }
    }

    // MARK: - Private
}
