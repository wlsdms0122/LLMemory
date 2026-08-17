//
//  FetchNoteHeaderOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// The catalog row's text fields — what a search projection is built from
// alongside the note's body.
struct FetchNoteHeaderOperation: GRDBReadOperation {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> (title: String, summary: String?)? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT title, summary FROM notes WHERE id = ?",
            arguments: [noteId]
        ) else {
            return nil
        }

        return (title: row["title"], summary: row["summary"] as String?)
    }

    // MARK: - Private
}
