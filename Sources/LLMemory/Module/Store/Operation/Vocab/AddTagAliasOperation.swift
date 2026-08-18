//
//  AddTagAliasOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct AddTagAliasOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, String, Int)
    let alias: String
    let canonical: String
    let now: Int

    // MARK: - Initializer
    init(alias: String, canonical: String, now: Int) {
        self.alias = alias
        self.canonical = canonical
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO tag_aliases (alias, canonical, created_at) VALUES (?, ?, ?)",
            arguments: [alias, canonical, now]
        )
    }

    // MARK: - Private
}
