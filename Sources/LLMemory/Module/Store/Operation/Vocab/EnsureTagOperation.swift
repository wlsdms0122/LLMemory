//
//  EnsureTagOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Vocabulary operations — tag vocab and tag aliases.
struct EnsureTagOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, Int?)
    let tag: String
    let now: Int?

    // MARK: - Initializer
    init(tag: String, now: Int? = nil) {
        self.tag = tag
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)

        try db.execute(
            sql: "INSERT OR IGNORE INTO tag_vocab (tag, created_at) VALUES (?, ?)",
            arguments: [tag, timestamp]
        )
    }

    // MARK: - Private
}
