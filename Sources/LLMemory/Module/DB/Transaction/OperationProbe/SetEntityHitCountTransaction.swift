//
//  SetEntityHitCountTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SetEntityHitCountTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let entity: String
    let hits: Int

    // MARK: - Initializer
    init(noteId: String, entity: String, hits: Int) {
        self.noteId = noteId
        self.entity = entity
        self.hits = hits
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(
            sql: "UPDATE entity_index SET hit_count = ? WHERE note_id = ? AND entity = ?",
            arguments: [hits, noteId, entity]
        )
    }

    // MARK: - Private
}
