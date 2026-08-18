//
//  DeleteNoteLinksOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct DeleteNoteLinksOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = String
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(
            sql: "DELETE FROM note_links WHERE src = ? OR dst = ?",
            arguments: [noteId, noteId]
        )
    }

    // MARK: - Private
}
