//
//  EnsureTagTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Vocabulary transactions — tag vocab and tag aliases.
struct EnsureTagTransaction: GRDBTransaction {
    // MARK: - Property
    let tag: String
    let now: Int?

    // MARK: - Initializer
    init(tag: String, now: Int? = nil) {
        self.tag = tag
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)

        try db.execute(
            sql: "INSERT OR IGNORE INTO tag_vocab (tag, created_at) VALUES (?, ?)",
            arguments: [tag, timestamp]
        )
    }

    // MARK: - Private
}
