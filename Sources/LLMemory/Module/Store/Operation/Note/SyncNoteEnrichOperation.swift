//
//  SyncNoteEnrichOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SyncNoteEnrichOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = String
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        guard try NoteExistsOperation(nid: noteId).execute(db) else { return }

        let enrich = try FetchNoteEnrichTextOperation(noteId: noteId).execute(db)

        try db.execute(
            sql: "UPDATE notes_fts SET enrich = ? WHERE id = ? AND section = ''",
            arguments: [enrich, noteId]
        )
    }

    // MARK: - Private
}
