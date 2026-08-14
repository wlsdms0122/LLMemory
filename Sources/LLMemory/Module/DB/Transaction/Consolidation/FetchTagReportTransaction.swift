//
//  FetchTagReportTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchTagReportTransaction: GRDBReadTransaction {
    // MARK: - Property
    let lowFreq: Int
    let limit: Int

    // MARK: - Initializer
    init(lowFreq: Int = 1, limit: Int = 40) {
        self.lowFreq = lowFreq
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> ConsolidateTagReport {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT tag, COUNT(*) c FROM tags GROUP BY tag ORDER BY c ASC, tag"
        )
        let all: [(String, Int)] = rows.map { row in (row["tag"] as String, row["c"] as Int) }
        let rare = all
            .filter { entry in entry.1 <= lowFreq }
            .prefix(limit)
            .map { entry in TagCount(tag: entry.0, count: entry.1) }
        let unused = try String.fetchAll(db, sql: """
            SELECT tv.tag FROM tag_vocab tv
            LEFT JOIN tags t ON t.tag = tv.tag WHERE t.tag IS NULL
            ORDER BY tv.tag
            """)
        
        return ConsolidateTagReport(rare: Array(rare), unused: unused)
    }

    // MARK: - Private
}
