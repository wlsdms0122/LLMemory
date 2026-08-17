//
//  FetchLinkDistributionOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchLinkDistributionOperation: GRDBReadOperation {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> LinkDistribution {
        let byKindRows = try Row.fetchAll(db, sql: """
            SELECT kind, COUNT(*) AS c, MIN(weight) AS mn, AVG(weight) AS av, MAX(weight) AS mx
            FROM note_links GROUP BY kind ORDER BY kind
            """)
        let byKind = byKindRows.map { row in
            (
                kind: row["kind"] as String,
                count: row["c"] as Int,
                min: row["mn"] as Double? ?? 0,
                avg: round((row["av"] as Double? ?? 0) * 1000) / 1000,
                max: row["mx"] as Double? ?? 0
            )
        }
        let bucketRow = try Row.fetchOne(db, sql: """
            SELECT
              SUM(CASE WHEN weight < 0.3 THEN 1 ELSE 0 END) AS w_lt_03,
              SUM(CASE WHEN weight >= 0.3 AND weight < 0.6 THEN 1 ELSE 0 END) AS w_03_06,
              SUM(CASE WHEN weight >= 0.6 AND weight < 0.9 THEN 1 ELSE 0 END) AS w_06_09,
              SUM(CASE WHEN weight >= 0.9 THEN 1 ELSE 0 END) AS w_ge_09
            FROM note_links
            """)
        let buckets: [String: Int] = [
            "[0.0-0.3)": bucketRow?["w_lt_03"] as Int? ?? 0,
            "[0.3-0.6)": bucketRow?["w_03_06"] as Int? ?? 0,
            "[0.6-0.9)": bucketRow?["w_06_09"] as Int? ?? 0,
            "[0.9- ]": bucketRow?["w_ge_09"] as Int? ?? 0
        ]
        let topRows = try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, COUNT(*) AS deg
            FROM note_links l
            JOIN notes n ON n.id IN (l.src, l.dst)
            GROUP BY n.id ORDER BY deg DESC, n.id LIMIT 5
            """)
        let topDegree = topRows.map { row in
            (
                id: row["id"] as String,
                title: row["title"] as String,
                degree: row["deg"] as Int
            )
        }

        return LinkDistribution(
            byKind: byKind,
            weightBuckets: buckets,
            topDegree: topDegree
        )
    }

    // MARK: - Private
}
