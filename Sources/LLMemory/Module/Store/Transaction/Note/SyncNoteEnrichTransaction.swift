//
//  SyncNoteEnrichTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SyncNoteEnrichTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard try NoteExistsTransaction(nid: noteId).perform(db) else { return }

        let enrich = try FetchNoteEnrichTextTransaction(noteId: noteId).perform(db)

        try db.execute(
            sql: "UPDATE notes_fts SET enrich = ? WHERE id = ? AND section = ''",
            arguments: [enrich, noteId]
        )
    }

    // MARK: - Private
}
