//
//  FetchNotePriorityTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Probes and small writes the operation handlers compose — each one row
// vocabulary the mutation engine validates and applies through.
struct FetchNotePriorityTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT priority FROM notes WHERE id = ?",
            arguments: [nid]
        )
    }

    // MARK: - Private
}
