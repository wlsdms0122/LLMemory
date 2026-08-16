//
//  DropNoteFTSTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Removes a note's search rows. The counterpart of ReindexNoteFTSTransaction,
// for a note the catalog no longer has.
struct DropNoteFTSTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [noteId])
    }

    // MARK: - Private
}
