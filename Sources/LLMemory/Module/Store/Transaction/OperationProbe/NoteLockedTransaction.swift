//
//  NoteLockedTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct NoteLockedTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT locked FROM notes WHERE id = ?",
            arguments: [nid]
        ) == 1
    }

    // MARK: - Private
}
