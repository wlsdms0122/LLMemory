//
//  SetSourceStalenessTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Records what the last drift check saw. Clearing the tracking entirely is
// the same statement's other half: a note with nothing checkable to compare
// against is not a note with fresh sources, it is a note without any.
struct SetSourceStalenessTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let stale: Bool?

    // MARK: - Initializer
    init(noteId: String, stale: Bool?) {
        self.noteId = noteId
        self.stale = stale
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard let stale else {
            try db.execute(sql: "DELETE FROM note_source WHERE note_id = ?", arguments: [noteId])

            return
        }

        try db.execute(
            sql: "UPDATE note_source SET source_stale = ? WHERE note_id = ?",
            arguments: [stale ? 1 : 0, noteId]
        )
    }

    // MARK: - Private
}
