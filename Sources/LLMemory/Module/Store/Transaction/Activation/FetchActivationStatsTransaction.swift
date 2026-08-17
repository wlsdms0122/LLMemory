//
//  FetchActivationStatsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchActivationStatsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> ActivationStats {
        let windows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_windows") ?? 0
        let labeled = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM activity_windows WHERE label IS NOT NULL"
        ) ?? 0
        let surfaced = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM retrieval_hits") ?? 0
        let used = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM retrieval_hits WHERE used_signal IS NOT NULL"
        ) ?? 0
        // Grouped by the id's first label, in SQLite: retrieval_hits is append-only
        // and outlives the events it came from, so the cost of this must follow the
        // number of branches, not the length of the log. The branch expression is
        // shared rather than spelled out here.
        let prefixRows = try Row.fetchAll(db, sql: """
            SELECT \(NoteAddress.branchSQL(column: "note_id")) AS prefix,
                   COUNT(*) AS surfaced,
                   SUM(CASE WHEN used_signal IS NOT NULL THEN 1 ELSE 0 END) AS used
            FROM retrieval_hits
            GROUP BY prefix ORDER BY surfaced DESC, prefix
            """)
        let byPrefix = prefixRows.map { row in
            ActivationStats.PrefixRow(
                prefix: row["prefix"],
                surfaced: row["surfaced"],
                used: row["used"] ?? 0
            )
        }

        return ActivationStats(
            windows: windows,
            labeledWindows: labeled,
            surfaced: surfaced,
            used: used,
            byPrefix: byPrefix
        )
    }

    // MARK: - Private
}
