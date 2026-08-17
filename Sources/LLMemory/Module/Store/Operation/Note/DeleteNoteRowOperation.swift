//
//  DeleteNoteRowOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct DeleteNoteRowOperation: GRDBOperation {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM notes WHERE id = ?", arguments: [nid])
        try db.execute(sql: "DELETE FROM notes_fts WHERE id = ?", arguments: [nid])
    }

    // MARK: - Private
}
