//
//  InheritSourceObservationTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct InheritSourceObservationTransaction: GRDBTransaction {
    // MARK: - Property
    let from: String
    let to: String

    // MARK: - Initializer
    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO note_source (note_id, source_hash, source_stale, decl_hash)
            SELECT c.note_id, p.source_hash, p.source_stale, p.decl_hash
            FROM note_source p JOIN note_source c
              ON c.note_id = ? AND p.note_id = ? AND p.decl_hash = c.decl_hash
            """, arguments: [to, from])
    }

    // MARK: - Private
}
