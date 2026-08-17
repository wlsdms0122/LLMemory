//
//  SetConfigValueTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Writes the row and only the row. The parameter caches catch up when the
// scope commits, so nothing here has to keep them in step.
struct SetConfigValueTransaction: GRDBTransaction {
    // MARK: - Property
    let key: String
    let value: String

    // MARK: - Initializer
    init(key: String, value: String) {
        self.key = key
        self.value = value
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try MetaRecord(key: Config.prefix + key, value: value).upsert(db)
    }

    // MARK: - Private
}
