//
//  FetchTopTagsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchTopTagsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Int
    let limit: Int

    // MARK: - Initializer
    init(limit: Int = 20) {
        self.limit = limit
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [(tag: String, count: Int)] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT tag, COUNT(*) c FROM tags GROUP BY tag ORDER BY c DESC, tag LIMIT ?",
            arguments: [limit]
        )

        return rows.map { row in (row["tag"] as String, row["c"] as Int) }
    }

    // MARK: - Private
}
