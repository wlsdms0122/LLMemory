//
//  EntityTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// entity_index transactions — the per-note entity registry and its
// freshness-gated lookup.
public struct EntityHit: Sendable {
    // MARK: - Property
    public let entity: String
    public let noteId: String
    public let axis: String?
    public let lastSeenAt: Int
    public let hitCount: Int
    public let title: String?
    public let summary: String?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct DeleteNoteEntitiesTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM entity_index WHERE note_id = ?", arguments: [noteId])
    }

    // MARK: - Private
}

struct ReconcileNoteEntitiesTransaction: GRDBTransaction {
    // MARK: - Property
    let entities: [String]
    let noteId: String
    let now: Int

    // MARK: - Initializer
    init(entities: [String], noteId: String, now: Int) {
        self.entities = entities
        self.noteId = noteId
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let want = entities.filter { entity in
            !entity.trimmingCharacters(in: .whitespaces).isEmpty
        }

        if want.isEmpty {
            try DeleteNoteEntitiesTransaction(noteId: noteId).perform(db)

            return
        }

        let placeholders = want.map { _ in "?" }.joined(separator: ",")

        try db.execute(
            sql: "DELETE FROM entity_index WHERE note_id = ? AND entity NOT IN (\(placeholders))",
            arguments: StatementArguments([noteId] + want)
        )

        for entity in want {
            try db.execute(sql: """
                INSERT OR IGNORE INTO entity_index (entity, note_id, last_seen_at, hit_count)
                VALUES (?, ?, ?, 1)
                """, arguments: [entity, noteId, now])
        }
    }

    // MARK: - Private
}

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
                SELECT ei.note_id, n.axis, ei.last_seen_at, ei.hit_count, n.title, n.summary
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
                        axis: row["axis"] as String?,
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
