//
//  Sources.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import CryptoKit

public enum NoteSources {
    struct SourceState {
        // MARK: - Property
        let noteId: String
        let fingerprint: String?
        let sourceStale: Bool
        let checkedAt: Int
        let paths: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct BulkVerifyResult {
        // MARK: - Property
        public var total: Int
        public var rechecked: Int
        public var stillFresh: Int
        public var becameStale: Int
        public var recovered: Int
        public var missing: Int
        public var unreadable: [String] = []
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func isDriftCheckable(_ ref: String) -> Bool {
        (ref as NSString).expandingTildeInPath.hasPrefix("/")
    }
    
    static func computeSha(path: URL) -> String? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        
        let digest = SHA256.hash(data: data)
        let hex = digest.map { byte in String(format: "%02x", byte) }.joined()
        
        return String(hex.prefix(16))
    }
    
    static func computeFingerprint(_ paths: [String]) -> String? {
        let checkable = paths.filter(isDriftCheckable)
        
        if checkable.isEmpty { return nil }
        
        let parts = checkable.map { path in
            "\(path):\(computeSha(path: resolve(path)) ?? "")"
        }
        let payload = parts.joined(separator: "\n").data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: payload)
        
        return String(digest.map { byte in String(format: "%02x", byte) }.joined().prefix(16))
    }
    
    static func computeDeclHash(_ paths: [String]) -> String? {
        let checkable = paths.filter(isDriftCheckable)
        
        if checkable.isEmpty { return nil }
        
        let payload = checkable.joined(separator: "\n").data(using: .utf8) ?? Data()
        let digest = SHA256.hash(data: payload)
        
        return String(digest.map { byte in String(format: "%02x", byte) }.joined().prefix(16))
    }
    
    static func projectRefs(
        _ db: Database,
        noteId: String,
        paths: [String],
        now: Int
    ) throws {
        guard let fingerprint = computeFingerprint(paths),
            let declHash = computeDeclHash(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )
            
            return
        }
        
        let stored = try String.fetchOne(
            db,
            sql: "SELECT decl_hash FROM note_source WHERE note_id = ?",
            arguments: [noteId]
        )
        
        if stored == declHash { return }
        
        try rebase(
            db,
            noteId: noteId,
            paths: paths,
            now: now,
            fingerprint: fingerprint,
            declHash: declHash
        )
    }
    
    static func rebase(
        _ db: Database,
        noteId: String,
        paths: [String],
        now: Int,
        fingerprint: String? = nil,
        declHash: String? = nil
    ) throws {
        guard let fingerprint = fingerprint ?? computeFingerprint(paths),
            let declHash = declHash ?? computeDeclHash(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )
            
            return
        }
        
        try db.execute(sql: """
            INSERT INTO note_source (note_id, source_hash, source_checked_at, source_stale, decl_hash)
            VALUES (?, ?, ?, 0, ?)
            ON CONFLICT(note_id) DO UPDATE SET
              source_hash = excluded.source_hash, source_checked_at = excluded.source_checked_at,
              source_stale = 0, decl_hash = excluded.decl_hash
            """, arguments: [noteId, fingerprint, now, declHash])
    }
    
    static func inheritObservation(_ db: Database, from: String, to: String) throws {
        try db.execute(sql: """
            INSERT OR REPLACE INTO note_source (note_id, source_hash, source_checked_at, source_stale, decl_hash)
            SELECT c.note_id, p.source_hash, p.source_checked_at, p.source_stale, p.decl_hash
            FROM note_source p JOIN note_source c
              ON c.note_id = ? AND p.note_id = ? AND p.decl_hash = c.decl_hash
            """, arguments: [to, from])
    }
    
    static func noteSourcePaths(_ db: Database, noteId: String) throws -> [String] {
        guard let relativePath = try String.fetchOne(
            db,
            sql: "SELECT path FROM notes WHERE id = ?",
            arguments: [noteId]
        ) else {
            return []
        }
        
        let notePath = Paths.brainRoot.appendingPathComponent(relativePath)
        
        return try Notes.requireNote(at: notePath).doc.source
    }
    
    static func verifyOne(_ db: Database, noteId: String, now: Int? = nil) throws -> Bool {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)
        let row = try Row.fetchOne(
            db,
            sql: "SELECT source_hash, decl_hash FROM note_source WHERE note_id = ?",
            arguments: [noteId]
        )
        
        guard let row, let stored = row["source_hash"] as String?, !stored.isEmpty else {
            return false
        }
        
        let paths = try noteSourcePaths(db, noteId: noteId)
        
        guard let currentDecl = computeDeclHash(paths),
            let current = computeFingerprint(paths)
        else {
            try db.execute(
                sql: "DELETE FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )
            
            return false
        }
        
        if currentDecl != (row["decl_hash"] as String?) {
            try rebase(
                db,
                noteId: noteId,
                paths: paths,
                now: timestamp,
                fingerprint: current,
                declHash: currentDecl
            )
            
            return false
        }
        
        let stale = current != stored
        
        try db.execute(
            sql: "UPDATE note_source SET source_stale = ?, source_checked_at = ? WHERE note_id = ?",
            arguments: [stale ? 1 : 0, timestamp, noteId]
        )
        
        return stale
    }
    
    static func staleNoteIds(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT note_id FROM note_source WHERE source_stale = 1"))
    }
    
    static func bulkVerify(_ db: Database, now overrideNow: Int? = nil) throws -> BulkVerifyResult {
        let now = overrideNow ?? Int(Date().timeIntervalSince1970)
        let rows = try Row.fetchAll(db, sql: """
            SELECT note_id AS id, source_hash, source_stale, decl_hash FROM note_source
            WHERE source_hash IS NOT NULL
            """)
        var result = BulkVerifyResult(
            total: rows.count,
            rechecked: 0,
            stillFresh: 0,
            becameStale: 0,
            recovered: 0,
            missing: 0
        )
        
        for row in rows {
            let noteId: String = row["id"]
            let stored: String? = row["source_hash"]
            let previousStale: Int = row["source_stale"] as Int? ?? 0
            let storedDecl: String? = row["decl_hash"]
            let allPaths: [String]
            do {
                allPaths = try noteSourcePaths(db, noteId: noteId)
            } catch {
                guard error is NoteUnreadable else { throw error }
                
                result.unreadable.append("\(noteId): \(error)")
                continue
            }
            
            let sourcePaths = allPaths.filter(isDriftCheckable)
            
            if sourcePaths.isEmpty {
                try db.execute(
                    sql: "DELETE FROM note_source WHERE note_id = ?",
                    arguments: [noteId]
                )
                continue
            }
            
            if computeDeclHash(allPaths) != storedDecl {
                try rebase(db, noteId: noteId, paths: allPaths, now: now)
                result.rechecked += 1
                
                if previousStale == 1 { result.recovered += 1 }
                
                continue
            }
            
            let anyExists = sourcePaths.contains { path in
                FileManager.default.fileExists(atPath: resolve(path).path)
            }
            let newStale: Int
            
            if !anyExists {
                result.missing += 1
                newStale = 1
            } else {
                let current = computeFingerprint(sourcePaths)
                newStale = (current == stored) ? 0 : 1
                
                if newStale == 0 { result.stillFresh += 1 }
                
                result.rechecked += 1
            }
            
            if newStale == 1 && previousStale == 0 {
                result.becameStale += 1
            } else if newStale == 0 && previousStale == 1 {
                result.recovered += 1
            }
            
            try db.execute(
                sql: "UPDATE note_source SET source_stale = ?, source_checked_at = ? WHERE note_id = ?",
                arguments: [newStale, now, noteId]
            )
        }
        
        return result
    }
    
    static func noteSourceState(_ db: Database, noteId: String) throws -> SourceState {
        let row = try Row.fetchOne(
            db,
            sql: "SELECT source_hash, source_stale, source_checked_at FROM note_source WHERE note_id = ?",
            arguments: [noteId]
        )
        
        guard let row else {
            return SourceState(
                noteId: noteId,
                fingerprint: nil,
                sourceStale: false,
                checkedAt: 0,
                paths: []
            )
        }
        
        return SourceState(
            noteId: noteId,
            fingerprint: row["source_hash"] as String?,
            sourceStale: (row["source_stale"] as Int? ?? 0) != 0,
            checkedAt: row["source_checked_at"] as Int? ?? 0,
            paths: try noteSourcePaths(db, noteId: noteId)
        )
    }
    
    // MARK: - Private
    private static func resolve(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
