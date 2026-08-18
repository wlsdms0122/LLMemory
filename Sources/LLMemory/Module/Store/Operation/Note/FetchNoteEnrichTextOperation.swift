//
//  FetchNoteEnrichTextOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteEnrichTextOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = String
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> String {
        let terms = try String.fetchAll(db, sql: """
            SELECT term FROM note_retrieval_terms
            WHERE note_id = ? AND status = 'active'
            ORDER BY kind, term
            """, arguments: [noteId])

        return terms.joined(separator: "\n")
    }

    // MARK: - Private
}
