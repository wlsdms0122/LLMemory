//
//  FetchNoteStaleStateOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteStaleStateOperation: GRDBReadOperation {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    // nil when the note is unknown.
    func execute(_ db: Database) throws -> Bool? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT stale FROM notes WHERE id = ?",
            arguments: [nid]
        ) else {
            return nil
        }

        return (row["stale"] as Int? ?? 0) != 0
    }

    // MARK: - Private
}
