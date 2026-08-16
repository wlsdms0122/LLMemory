//
//  PrefixStatsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Everything at or under one address. The prefix itself counts — `a.b` is a
// note as well as the parent of `a.b.c`, and asking about a branch means asking
// about all of it.
struct PrefixStatsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let prefix: String

    // MARK: - Initializer
    init(prefix: String) {
        self.prefix = prefix
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> PrefixStats {
        let row = try Row.fetchOne(db, sql: """
            SELECT COUNT(*) AS total,
                   SUM(CASE WHEN \(Policy.stale()) THEN 1 ELSE 0 END) AS stale_count,
                   SUM(CASE WHEN \(Policy.eager()) THEN 1 ELSE 0 END) AS eager_count,
                   COALESCE(AVG(n.word_count), 0) AS avg_words,
                   COALESCE(MAX(n.word_count), 0) AS max_words,
                   COALESCE(AVG(n.section_count), 0) AS avg_sections,
                   COALESCE(SUM(COALESCE(u.hit_count, 0)), 0) AS total_hits
            FROM notes n LEFT JOIN note_usage u ON u.note_id = n.id
            WHERE n.id = ? OR n.id GLOB ?
            """, arguments: [prefix, prefix + ".*"])!
        // Same membership as NoteAddress.id(_:isWithin:) — GLOB is its SQL spelling,
        // and `.*` matches any remaining labels because GLOB's * crosses dots.

        return PrefixStats(
            total: row["total"] as Int? ?? 0,
            stale: row["stale_count"] as Int? ?? 0,
            eager: row["eager_count"] as Int? ?? 0,
            avgWords: (round((row["avg_words"] as Double? ?? 0) * 10) / 10),
            maxWords: row["max_words"] as Int? ?? 0,
            avgSections: (round((row["avg_sections"] as Double? ?? 0) * 10) / 10),
            totalHits: row["total_hits"] as Int? ?? 0
        )
    }

    // MARK: - Private
}
