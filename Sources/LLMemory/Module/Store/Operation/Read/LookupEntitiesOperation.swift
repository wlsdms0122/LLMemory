//
//  LookupEntitiesOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct LookupEntitiesOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = (String?, Int)
    let name: String?
    let limit: Int

    // MARK: - Initializer
    init(name: String?, limit: Int) {
        self.name = name
        self.limit = limit
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [EntityHit] {
        let sql: String
        let arguments: [DatabaseValueConvertible?]

        if let name {
            sql = """
                SELECT ei.entity, ei.note_id, n.title, n.summary, ei.last_seen_at, ei.hit_count
                FROM entity_index ei LEFT JOIN notes n ON n.id = ei.note_id
                WHERE ei.entity = ? ORDER BY ei.last_seen_at DESC, ei.note_id ASC LIMIT ?
                """
            arguments = [name, limit]
        } else {
            sql = """
                SELECT ei.entity, ei.note_id, n.title, n.summary, ei.last_seen_at, ei.hit_count
                FROM entity_index ei LEFT JOIN notes n ON n.id = ei.note_id
                ORDER BY ei.last_seen_at DESC, ei.entity ASC, ei.note_id ASC LIMIT ?
                """
            arguments = [limit]
        }

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            .map { row in
                EntityHit(
                    entity: row["entity"],
                    noteId: row["note_id"],
                    lastSeenAt: row["last_seen_at"] as Int? ?? 0,
                    hitCount: row["hit_count"] as Int? ?? 0,
                    title: row["title"] as String?,
                    summary: row["summary"] as String?
                )
            }
    }

    // MARK: - Private
}
