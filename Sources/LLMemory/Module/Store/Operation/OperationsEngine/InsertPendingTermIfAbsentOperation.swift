//
//  InsertPendingTermIfAbsentOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct InsertPendingTermIfAbsentOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, String, String, String?, Int)
    let noteId: String
    let kind: String
    let term: String
    let provenance: String?
    let now: Int

    // MARK: - Initializer
    init(noteId: String, kind: String, term: String, provenance: String?, now: Int) {
        self.noteId = noteId
        self.kind = kind
        self.term = term
        self.provenance = provenance
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR IGNORE INTO note_retrieval_terms
              (note_id, kind, term, status, provenance, created_at)
            VALUES (?, ?, ?, 'pending', ?, ?)
            """, arguments: [noteId, kind, term, provenance, now])
    }

    // MARK: - Private
}
