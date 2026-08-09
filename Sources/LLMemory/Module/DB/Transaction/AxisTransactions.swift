//
//  AxisTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct FetchAxesWithCountsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(axis: String, description: String?, count: Int)] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT a.axis, a.description, COALESCE(COUNT(n.id), 0) AS c
            FROM axes a LEFT JOIN notes n ON n.axis = a.axis
            GROUP BY a.axis ORDER BY a.axis
            """)

        return rows.map { row in
            (
                axis: row["axis"] as String,
                description: row["description"] as String?,
                count: row["c"] as Int
            )
        }
    }

    // MARK: - Private
}
