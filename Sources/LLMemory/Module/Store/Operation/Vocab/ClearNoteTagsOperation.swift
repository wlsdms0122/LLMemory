//
//  ClearNoteTagsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ClearNoteTagsOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = String
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM tags WHERE note_id = ?", arguments: [noteId])
    }

    // MARK: - Private
}
