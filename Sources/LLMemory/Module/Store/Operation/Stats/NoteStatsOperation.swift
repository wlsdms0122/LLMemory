//
//  NoteStatsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct NoteStatsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = String
    let id: String

    // MARK: - Initializer
    init(id: String) {
        self.id = id
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> NoteStats? {
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
