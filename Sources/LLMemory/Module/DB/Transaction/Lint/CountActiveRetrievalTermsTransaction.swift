//
//  CountActiveRetrievalTermsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct CountActiveRetrievalTermsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM note_retrieval_terms WHERE note_id = ? AND status = 'active'",
            arguments: [noteId]
        ) ?? 0
    }

    // MARK: - Private
}
