//
//  TagVocabExistsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct TagVocabExistsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM tag_vocab WHERE tag = ?",
            arguments: [tag]
        ) != nil
    }

    // MARK: - Private
}
