//
//  FetchTagCooccurrenceOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchTagCooccurrenceOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = ([String], Int)
    let tags: [String]
    let limit: Int

    // MARK: - Initializer
    init(tags: [String], limit: Int = 15) {
        self.tags = tags
        self.limit = limit
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [(tagA: String, tagB: String, count: Int)] {
        if tags.isEmpty { return [] }

        let placeholders = Array(repeating: "?", count: tags.count).joined(separator: ",")
        var arguments: [DatabaseValueConvertible?] = []
        arguments.append(contentsOf: tags)
        arguments.append(contentsOf: tags)
        arguments.append(limit)

        let rows = try Row.fetchAll(db, sql: """
            SELECT t1.tag AS tag_a, t2.tag AS tag_b, COUNT(*) AS c
            FROM tags t1 JOIN tags t2 ON t1.note_id = t2.note_id AND t1.tag < t2.tag
            WHERE t1.tag IN (\(placeholders)) OR t2.tag IN (\(placeholders))
            GROUP BY t1.tag, t2.tag
            ORDER BY c DESC, tag_a ASC, tag_b ASC LIMIT ?
            """, arguments: StatementArguments(arguments))

        return rows.map { row in
            (row["tag_a"] as String, row["tag_b"] as String, row["c"] as Int)
        }
    }

    // MARK: - Private
}
