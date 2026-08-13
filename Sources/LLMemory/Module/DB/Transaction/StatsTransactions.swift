//
//  StatsTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Observation transactions — per-note, per-prefix, and corpus-wide stats.
public struct NoteStats: Sendable {
    // MARK: - Property
    public let id: String
    public let title: String
    public let summary: String?
    public let priority: String
    public let createdAt: Int
    public let editedAt: Int
    public let ageDays: Int?
    public let sinceEditDays: Int?
    public let sinceRetrievalDays: Int?
    public let hitCount: Int
    public let wordCount: Int
    public let sectionCount: Int
    public let stale: Bool
    public let tagCount: Int
    public let linkCount: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct PrefixStats: Sendable {
    // MARK: - Property
    public let total: Int
    public let stale: Int
    public let eager: Int
    public let avgWords: Double
    public let maxWords: Int
    public let avgSections: Double
    public let totalHits: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct OverallStats: Sendable {
    // MARK: - Property
    public let total: Int
    public let stale: Int
    public let tree: [TreeRow]
    public let hitNonZero: Int
    public let hitZero: Int
    public let hitAvg: Double
    public let hitMax: Int
    public let avgWords: Double
    public let maxWords: Int
    public let avgSections: Double
    public let activation: ActivationStats

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct NoteStatsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let id: String

    // MARK: - Initializer
    init(id: String) {
        self.id = id
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> NoteStats? {
        let row = try Row.fetchOne(db, sql: """
            SELECT notes.id, title, summary, priority,
                   u.created_at, edited_at, u.hit_count, u.last_retrieved_at,
                   word_count, section_count,
                   COALESCE(stale, 0) AS s,
                   (SELECT COUNT(*) FROM tags WHERE note_id = notes.id) AS tag_count,
                   (SELECT COUNT(*) FROM note_links WHERE src = notes.id OR dst = notes.id) AS link_count
            FROM notes LEFT JOIN note_usage u ON u.note_id = notes.id WHERE notes.id = ?
            """, arguments: [id])

        guard let row else { return nil }

        let now = Int(Date().timeIntervalSince1970)
        let created: Int = row["created_at"] as Int? ?? 0
        let edited: Int = row["edited_at"] as Int? ?? 0
        let lastRetrieved: Int = row["last_retrieved_at"] as Int? ?? 0

        return NoteStats(
            id: row["id"],
            title: row["title"],
            summary: row["summary"] as String?,
            priority: row["priority"],
            createdAt: created,
            editedAt: edited,
            ageDays: created > 0 ? (now - created) / 86400 : nil,
            sinceEditDays: edited > 0 ? (now - edited) / 86400 : nil,
            sinceRetrievalDays: lastRetrieved > 0 ? (now - lastRetrieved) / 86400 : nil,
            hitCount: row["hit_count"] as Int? ?? 0,
            wordCount: row["word_count"] as Int? ?? 0,
            sectionCount: row["section_count"] as Int? ?? 0,
            stale: (row["s"] as Int? ?? 0) != 0,
            tagCount: row["tag_count"] as Int? ?? 0,
            linkCount: row["link_count"] as Int? ?? 0
        )
    }

    // MARK: - Private
}

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

struct OverallStatsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> OverallStats {
        let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes") ?? 0
        let stale = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM notes WHERE \(Policy.stale(""))"
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
