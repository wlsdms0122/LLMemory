//
//  OverallStatsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct OverallStatsTransaction: GRDBReadTransaction {
    private let policy = Policy()

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> OverallStats {
        let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes") ?? 0
        let stale = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM notes WHERE \(policy.stale(""))"
        ) ?? 0
        let tree = try FetchTreeTransaction().perform(db)
        let hitRow = try Row.fetchOne(db, sql: """
            SELECT COALESCE(SUM(CASE WHEN COALESCE(u.hit_count, 0) > 0 THEN 1 ELSE 0 END), 0) AS nz,
                   COALESCE(SUM(CASE WHEN COALESCE(u.hit_count, 0) = 0 THEN 1 ELSE 0 END), 0) AS z,
                   COALESCE(AVG(COALESCE(u.hit_count, 0)), 0) AS avg,
                   COALESCE(MAX(COALESCE(u.hit_count, 0)), 0) AS mx
            FROM notes n LEFT JOIN note_usage u ON u.note_id = n.id
            """)!
        let sizeRow = try Row.fetchOne(db, sql: """
            SELECT COALESCE(AVG(word_count), 0) AS aw,
                   COALESCE(MAX(word_count), 0) AS mw,
                   COALESCE(AVG(section_count), 0) AS as_
            FROM notes
            """)!

        return OverallStats(
            total: total,
            stale: stale,
            tree: tree,
            hitNonZero: hitRow["nz"] as Int? ?? 0,
            hitZero: hitRow["z"] as Int? ?? 0,
            hitAvg: round((hitRow["avg"] as Double? ?? 0) * 100) / 100,
            hitMax: hitRow["mx"] as Int? ?? 0,
            avgWords: round((sizeRow["aw"] as Double? ?? 0) * 10) / 10,
            maxWords: sizeRow["mw"] as Int? ?? 0,
            avgSections: round((sizeRow["as_"] as Double? ?? 0) * 10) / 10,
            activation: try FetchActivationStatsTransaction().perform(db)
        )
    }

    // MARK: - Private
}
