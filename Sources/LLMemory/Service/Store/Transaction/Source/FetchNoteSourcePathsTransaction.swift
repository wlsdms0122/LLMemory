//
//  FetchNoteSourcePathsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteSourcePathsTransaction: GRDBBrainReadTransaction {
    // MARK: - Property
    let noteId: String

    private let noteFile = NoteFile()

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> [String] {
        guard try NoteExistsTransaction(nid: noteId).perform(db) else { return [] }

        return try noteFile.requireNote(at: brain.layout.file(forId: noteId)).doc.source
    }

    // MARK: - Private
}
