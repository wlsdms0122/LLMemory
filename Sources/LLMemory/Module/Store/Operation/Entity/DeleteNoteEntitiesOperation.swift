//
//  DeleteNoteEntitiesOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct DeleteNoteEntitiesOperation: GRDBOperation {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM entity_index WHERE note_id = ?", arguments: [noteId])
    }

    // MARK: - Private
}
