//
//  FetchEntityHitsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchEntityHitsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let entities: [String]
    let limitPerEntity: Int

    // MARK: - Initializer
    init(entities: [String], limitPerEntity: Int = 5) {
        self.entities = entities
        self.limitPerEntity = limitPerEntity
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [EntityHit] {
        guard !entities.isEmpty else { return [] }

        var hits: [EntityHit] = []

        for entity in entities where !entity.isEmpty {
            var sql = """
                SELECT ei.note_id, ei.last_seen_at, ei.hit_count, n.title, n.summary
                FROM entity_index ei
                JOIN notes n ON n.id = ei.note_id
                WHERE ei.entity = ?
                AND \(Policy.fresh())
                """
            sql += " ORDER BY ei.last_seen_at DESC, ei.note_id ASC LIMIT ?"

            let rows = try Row.fetchAll(db, sql: sql, arguments: [entity, limitPerEntity])

            for row in rows {
                hits.append(
                    EntityHit(
                        entity: entity,
                        noteId: row["note_id"],
                        lastSeenAt: row["last_seen_at"] as Int? ?? 0,
                        hitCount: row["hit_count"] as Int? ?? 0,
                        title: row["title"] as String?,
                        summary: row["summary"] as String?
                    )
                )
            }
        }

        return hits
    }

    // MARK: - Private
}
