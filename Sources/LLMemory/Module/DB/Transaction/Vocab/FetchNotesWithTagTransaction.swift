//
//  FetchNotesWithTagTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNotesWithTagTransaction: GRDBReadTransaction {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT DISTINCT note_id FROM tags WHERE tag = ?",
            arguments: [tag]
        )
    }

    // MARK: - Private
}
