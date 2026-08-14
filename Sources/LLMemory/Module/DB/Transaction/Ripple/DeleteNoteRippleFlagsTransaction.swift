//
//  DeleteNoteRippleFlagsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct DeleteNoteRippleFlagsTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM ripple_flags WHERE note_id = ?", arguments: [noteId])
    }

    // MARK: - Private
}
