//
//  Ripple.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

enum Ripple {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    @discardableResult
    static func flagInboundReferrers(
        _ db: Database,
        targetId: String,
        reason: String,
        now: Int
    ) throws -> Int {
        let referrers = try String.fetchAll(db, sql: """
            SELECT DISTINCT src FROM note_links WHERE dst = ? AND src != ? AND kind = ?
            """, arguments: [targetId, targetId, Links.kindReference])
        
        for referrer in referrers {
            try addFlag(db, noteId: referrer, kind: "stale_ref", reason: reason, now: now)
        }
        
        return referrers.count
    }
    
    static func deleteForNote(_ db: Database, noteId: String) throws {
        try db.execute(sql: "DELETE FROM ripple_flags WHERE note_id = ?", arguments: [noteId])
    }
    
    static func addFlag(
        _ db: Database,
        noteId: String,
        kind: String,
        reason: String,
        now: Int
    ) throws {
        try insertOrIncrement(
            db,
            noteId: noteId,
            kind: kind,
            reason: reason.unicodeScalarPrefix(200),
            now: now
        )
    }
    
    @discardableResult
    static func resolve(
        _ db: Database,
        noteId: String,
        kind: String,
        reason: String?,
        now: Int
    ) throws -> Int {
        try db.execute(sql: """
            UPDATE ripple_flags SET resolved_at = ?
            WHERE note_id = ? AND flag = ? AND resolved_at IS NULL
            """, arguments: [now, noteId, kind])
        
        let resolved = db.changesCount
        
        if resolved > 0 {
            let trimmed = reason?.unicodeScalarPrefix(200)
            
            try db.execute(sql: """
                INSERT INTO note_lifecycle_events (note_id, kind, reason, created_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [noteId, "flag_resolved", "\(kind): \(trimmed ?? "")", now])
        }
        
        return resolved
    }
    
    // MARK: - Private
    private static func insertOrIncrement(
        _ db: Database,
        noteId: String,
        kind: String,
        reason: String,
        now: Int
    ) throws {
        let stateRow = try Row.fetchOne(db, sql: """
            SELECT (resolved_at IS NOT NULL) AS resolved
            FROM ripple_flags WHERE note_id = ? AND flag = ?
            """, arguments: [noteId, kind])
        let isReoccurrence: Bool
        
        if let stateRow {
            isReoccurrence = (stateRow["resolved"] as Int? ?? 0) == 1
        } else {
            isReoccurrence = false
        }
        
        let isNew = stateRow == nil
        
        try db.execute(sql: """
            INSERT INTO ripple_flags (note_id, flag, reason, created_at, last_flagged_at, flag_count, resolved_at)
            VALUES (?, ?, ?, ?, ?, 1, NULL)
            ON CONFLICT(note_id, flag) DO UPDATE SET
              reason = excluded.reason,
              last_flagged_at = excluded.last_flagged_at,
              flag_count = ripple_flags.flag_count + 1,
              resolved_at = NULL
            """, arguments: [noteId, kind, reason, now, now])
        
        if isNew || isReoccurrence {
            try db.execute(sql: """
                INSERT INTO note_lifecycle_events (note_id, kind, reason, created_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [noteId, "flagged", "\(kind): \(reason)", now])
        }
    }
}
