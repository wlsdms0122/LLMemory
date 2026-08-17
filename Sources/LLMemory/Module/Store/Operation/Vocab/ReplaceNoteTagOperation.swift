//
//  ReplaceNoteTagOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ReplaceNoteTagOperation: GRDBOperation {
    // MARK: - Property
    let noteId: String
    let fromTag: String
    let toTag: String

    // MARK: - Initializer
    init(noteId: String, fromTag: String, toTag: String) {
        self.noteId = noteId
        self.fromTag = fromTag
        self.toTag = toTag
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(
            sql: "DELETE FROM tags WHERE note_id = ? AND tag = ?",
            arguments: [noteId, fromTag]
        )
        try db.execute(
            sql: "INSERT OR IGNORE INTO tags (note_id, tag) VALUES (?, ?)",
            arguments: [noteId, toTag]
        )
    }

    // MARK: - Private
}
