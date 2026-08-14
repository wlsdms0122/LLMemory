//
//  NoteExistsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct NoteExistsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT 1 FROM notes WHERE id = ?", arguments: [nid]) != nil
    }

    // MARK: - Private
}
