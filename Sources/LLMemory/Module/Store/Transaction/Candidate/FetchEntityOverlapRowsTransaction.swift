//
//  FetchEntityOverlapRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchEntityOverlapRowsTransaction: GRDBReadTransaction {
    struct EntityOverlap {
        // MARK: - Property
        let id: String
        let title: String
        let summary: String?
        let intersection: Int
        let size: Int

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [EntityOverlap] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, n.summary,
                   (SELECT COUNT(*) FROM entity_index e1
                     JOIN entity_index e2 ON e1.entity = e2.entity
                     WHERE e1.note_id = ? AND e2.note_id = n.id) AS inter,
                   (SELECT COUNT(*) FROM entity_index WHERE note_id = n.id) AS sz
            FROM notes n
            WHERE n.id != ? AND \(Policy.surface())
            """, arguments: [nid, nid]).map { row in
            EntityOverlap(
                id: row["id"],
                title: row["title"],
                summary: row["summary"] as String?,
                intersection: row["inter"] as Int? ?? 0,
                size: row["sz"] as Int? ?? 0
            )
        }
    }

    // MARK: - Private
}
