//
//  FetchTagUsageOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchTagUsageOperation: GRDBReadOperation {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [(tag: String, c: Int)] {
        try Row.fetchAll(db, sql: "SELECT tag, COUNT(*) c FROM tags GROUP BY tag")
            .map { row in (row["tag"], row["c"] as Int? ?? 0) }
    }

    // MARK: - Private
}
