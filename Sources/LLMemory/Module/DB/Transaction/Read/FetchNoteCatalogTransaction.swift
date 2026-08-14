//
//  FetchNoteCatalogTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteCatalogTransaction: GRDBReadTransaction {
    // MARK: - Property
    let ids: [String]

    // MARK: - Initializer
    init(ids: [String]) {
        self.ids = ids
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: CatalogNote] {
        guard !ids.isEmpty else { return [:] }

        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let rows = try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, n.summary, n.priority,
                   COALESCE(u.hit_count, 0) AS hit_count,
                   COALESCE(u.created_at, 0) AS created_at, n.edited_at
            FROM notes n LEFT JOIN note_usage u ON u.note_id = n.id
            WHERE n.id IN (\(placeholders))
            """, arguments: StatementArguments(ids))
        var catalog: [String: CatalogNote] = [:]

        for row in rows {
            catalog[row["id"] as String] = CatalogNote(
                id: row["id"],
                path: Paths.relativeFile(forId: row["id"] as String),
                title: row["title"],
                summary: row["summary"] as String?,
                priority: row["priority"],
                hitCount: row["hit_count"] as Int? ?? 0,
                createdAt: row["created_at"] as Int? ?? 0,
                editedAt: row["edited_at"] as Int? ?? 0
            )
        }

        return catalog
    }

    // MARK: - Private
}
