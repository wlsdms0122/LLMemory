//
//  FetchActiveTermRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchActiveTermRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(kind: String, term: String, provenance: String?)] {
        try Row.fetchAll(db, sql: """
            SELECT kind, term, provenance FROM note_retrieval_terms WHERE note_id = ? AND status = 'active'
            """, arguments: [noteId])
            .map { row in (kind: row["kind"], term: row["term"], provenance: row["provenance"]) }
    }

    // MARK: - Private
}
