//
//  Entities.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Entities {
    public struct Hit {
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
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func deleteForNote(_ db: Database, noteId: String) throws {
        try db.execute(sql: "DELETE FROM entity_index WHERE note_id = ?", arguments: [noteId])
    }
    
    static func reconcile(
        _ db: Database,
        entities: [String],
        noteId: String,
        now: Int
    ) throws {
        let want = entities.filter { entity in
            !entity.trimmingCharacters(in: .whitespaces).isEmpty
        }
        
        if want.isEmpty {
            try deleteForNote(db, noteId: noteId)
            
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
    
    static func hits(
        _ db: Database,
        entities: [String],
        limitPerEntity: Int = 5
    ) throws -> [Hit] {
        guard !entities.isEmpty else { return [] }
        
        var hits: [Hit] = []
        
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
                    Hit(
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
