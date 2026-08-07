//
//  NoteMeta.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

enum NoteMeta {
    static func get(
        _ db: Database,
        noteId: String,
        namespace: String,
        key: String
    ) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT value FROM note_meta WHERE note_id = ? AND namespace = ? AND key = ?",
            arguments: [noteId, namespace, key]
        )
    }
    
    static func getAll(
        _ db: Database,
        noteId: String,
        namespace: String? = nil
    ) throws -> [String: [String: String]] {
        if let namespace {
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT key, value FROM note_meta WHERE note_id = ? AND namespace = ?",
                arguments: [noteId, namespace]
            )
            var inner: [String: String] = [:]
            
            for row in rows { inner[row["key"]] = row["value"] }
            
            return [namespace: inner]
        }
        
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT namespace, key, value FROM note_meta WHERE note_id = ?
                ORDER BY namespace, key
                """,
            arguments: [noteId]
        )
        var values: [String: [String: String]] = [:]
        
        for row in rows {
            let namespace: String = row["namespace"]
            let key: String = row["key"]
            let value: String = row["value"]
            values[namespace, default: [:]][key] = value
        }
        
        return values
    }
    
    static func setValue(
        _ db: Database,
        noteId: String,
        namespace: String,
        key: String,
        value: String,
        now: Int
    ) throws {
        try db.execute(sql: """
            INSERT INTO note_meta (note_id, namespace, key, value, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(note_id, namespace, key) DO UPDATE SET
              value = excluded.value, updated_at = excluded.updated_at
            """, arguments: [noteId, namespace, key, value, now])
    }
    
    @discardableResult
    static func delete(
        _ db: Database,
        noteId: String,
        namespace: String,
        key: String
    ) throws -> Int {
        try db.execute(
            sql: "DELETE FROM note_meta WHERE note_id = ? AND namespace = ? AND key = ?",
            arguments: [noteId, namespace, key]
        )
        
        return db.changesCount
    }
    
    static func findByKV(
        _ db: Database,
        namespace: String,
        key: String,
        value: String? = nil,
        limit: Int = 100
    ) throws -> [(noteId: String, value: String)] {
        let rows: [Row]
        
        if let value {
            rows = try Row.fetchAll(
                db,
                sql: "SELECT note_id, value FROM note_meta WHERE namespace = ? AND key = ? AND value = ? ORDER BY note_id LIMIT ?",
                arguments: [namespace, key, value, limit]
            )
        } else {
            rows = try Row.fetchAll(
                db,
                sql: "SELECT note_id, value FROM note_meta WHERE namespace = ? AND key = ? ORDER BY note_id LIMIT ?",
                arguments: [namespace, key, limit]
            )
        }
        
        return rows.map { row in (noteId: row["note_id"], value: row["value"]) }
    }
}
