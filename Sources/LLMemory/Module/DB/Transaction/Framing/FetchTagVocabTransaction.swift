//
//  FetchTagVocabTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchTagVocabTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT tag FROM tag_vocab ORDER BY tag")
    }

    // MARK: - Private
}
