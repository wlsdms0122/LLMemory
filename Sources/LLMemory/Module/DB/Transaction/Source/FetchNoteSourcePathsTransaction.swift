//
//  FetchNoteSourcePathsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteSourcePathsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    private let noteFiles = Notes()

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        guard try NoteExistsTransaction(nid: noteId).perform(db) else { return [] }

        return try noteFiles.requireNote(at: Paths.file(forId: noteId)).doc.source
    }

    // MARK: - Private
}
