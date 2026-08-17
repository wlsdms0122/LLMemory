//
//  SetNoteStaleOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SetNoteStaleOperation: GRDBOperation {
    // MARK: - Property
    let nid: String
    let stale: Bool

    // MARK: - Initializer
    init(nid: String, stale: Bool) {
        self.nid = nid
        self.stale = stale
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(
            sql: "UPDATE notes SET stale = ? WHERE id = ?",
            arguments: [stale ? 1 : 0, nid]
        )
    }

    // MARK: - Private
}
