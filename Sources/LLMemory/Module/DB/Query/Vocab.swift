//
//  Vocab.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

enum Vocab {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    static func ensureAxis(
        _ db: Database,
        axis: String,
        description: String? = nil,
        now: Int? = nil
    ) throws {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)
        let description = description ?? "(auto-created)"
        
        try db.execute(
            sql: """
            INSERT INTO axes (axis, description, created_at) VALUES (?, ?, ?)
            ON CONFLICT(axis) DO UPDATE SET
              description = CASE
                WHEN axes.description IS NULL OR axes.description = '' OR axes.description = '(auto-created)'
                  THEN excluded.description
                ELSE axes.description
              END
            """,
            arguments: [axis, description, timestamp]
        )
    }
    
    static func ensureTag(_ db: Database, tag: String, now: Int? = nil) throws {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)
        
        try db.execute(
            sql: "INSERT OR IGNORE INTO tag_vocab (tag, created_at) VALUES (?, ?)",
            arguments: [tag, timestamp]
        )
    }
    
    static func canonicalizeTag(_ db: Database, tag: String) throws -> String {
        let canonical = try String.fetchOne(
            db,
            sql: "SELECT canonical FROM tag_aliases WHERE alias = ?",
            arguments: [tag]
        )
        
        return canonical ?? tag
    }
    
    static func listAxesNames(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT axis FROM axes"))
    }
    
    static func axisExists(_ db: Database, axis: String) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT 1 FROM axes WHERE axis = ?", arguments: [axis]) != nil
    }
    
    static func getAxis(
        _ db: Database,
        axis: String
    ) throws -> (description: String?, createdAt: Int)? {
        let row = try Row.fetchOne(
            db,
            sql: "SELECT description, created_at FROM axes WHERE axis = ?",
            arguments: [axis]
        )
        
        guard let row else { return nil }
        
        return (row["description"] as String?, row["created_at"] as Int)
    }
    
    static func setAxisDescription(_ db: Database, axis: String, description: String) throws {
        try db.execute(
            sql: "UPDATE axes SET description = ? WHERE axis = ?",
            arguments: [description, axis]
        )
    }
    
    static func createAxis(
        _ db: Database,
        axis: String,
        description: String,
        createdAt: Int
    ) throws {
        try db.execute(
            sql: "INSERT INTO axes (axis, description, created_at) VALUES (?, ?, ?)",
            arguments: [axis, description, createdAt]
        )
    }
    
    static func deleteAxis(_ db: Database, axis: String) throws {
        try db.execute(sql: "DELETE FROM axes WHERE axis = ?", arguments: [axis])
    }
    
    static func pruneEmptyAxes(
        _ db: Database,
        protected: Set<String> = []
    ) throws -> [String] {
        let rows = try String.fetchAll(db, sql: """
            SELECT a.axis FROM axes a
            LEFT JOIN notes n ON n.axis = a.axis
            GROUP BY a.axis
            HAVING COUNT(n.id) = 0
            """)
        let pruned = rows.filter { axis in !protected.contains(axis) }
        
        for axis in pruned {
            try db.execute(sql: "DELETE FROM axes WHERE axis = ?", arguments: [axis])
        }
        
        return pruned
    }
    
    static func retireTag(_ db: Database, tag: String, successor: String) throws {
        try db.execute(
            sql: "DELETE FROM tag_aliases WHERE canonical = ? AND alias = ?",
            arguments: [tag, successor]
        )
        try db.execute(
            sql: "UPDATE tag_aliases SET canonical = ? WHERE canonical = ?",
            arguments: [successor, tag]
        )
        try db.execute(sql: "DELETE FROM tag_vocab WHERE tag = ?", arguments: [tag])
    }
    
    static func tagVocabExists(_ db: Database, tag: String) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM tag_vocab WHERE tag = ?",
            arguments: [tag]
        ) != nil
    }
    
    static func tagInUse(_ db: Database, tag: String) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM tags WHERE tag = ? LIMIT 1",
            arguments: [tag]
        ) != nil
    }
    
    static func pruneUnusedVocabTags(
        _ db: Database,
        protected: Set<String> = []
    ) throws -> [String] {
        var protectedTags = protected
        // Canonicals of tag_aliases are always protected for referential integrity.
        let canonicals = try String.fetchAll(db, sql: "SELECT DISTINCT canonical FROM tag_aliases")
        protectedTags.formUnion(canonicals)
        
        let rows = try String.fetchAll(db, sql: """
            SELECT tv.tag FROM tag_vocab tv
            LEFT JOIN tags t ON t.tag = tv.tag WHERE t.tag IS NULL
            """)
        let pruned = rows.filter { tag in !protectedTags.contains(tag) }
        
        for tag in pruned {
            try db.execute(sql: "DELETE FROM tag_vocab WHERE tag = ?", arguments: [tag])
        }
        
        return pruned
    }
    
    static func addTagAlias(
        _ db: Database,
        alias: String,
        canonical: String,
        now: Int
    ) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO tag_aliases (alias, canonical, created_at) VALUES (?, ?, ?)",
            arguments: [alias, canonical, now]
        )
    }
    
    static func clearTagsForNote(_ db: Database, noteId: String) throws {
        try db.execute(sql: "DELETE FROM tags WHERE note_id = ?", arguments: [noteId])
    }
    
    static func replaceTagForNote(
        _ db: Database,
        noteId: String,
        fromTag: String,
        toTag: String
    ) throws {
        try db.execute(
            sql: "DELETE FROM tags WHERE note_id = ? AND tag = ?",
            arguments: [noteId, fromTag]
        )
        try db.execute(
            sql: "INSERT OR IGNORE INTO tags (note_id, tag) VALUES (?, ?)",
            arguments: [noteId, toTag]
        )
    }
    
    static func notesWithTag(_ db: Database, tag: String) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT DISTINCT note_id FROM tags WHERE tag = ?",
            arguments: [tag]
        )
    }
    
    static func pathsWithTag(_ db: Database, tag: String) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT n.path FROM notes n JOIN tags t ON t.note_id = n.id WHERE t.tag = ?
            """, arguments: [tag])
    }
    
    static func cooccurFor(
        _ db: Database,
        tags: [String],
        limit: Int = 15
    ) throws -> [(tagA: String, tagB: String, count: Int)] {
        if tags.isEmpty { return [] }
        
        let placeholders = Array(repeating: "?", count: tags.count).joined(separator: ",")
        var arguments: [DatabaseValueConvertible?] = []
        arguments.append(contentsOf: tags)
        arguments.append(contentsOf: tags)
        arguments.append(limit)
        
        let rows = try Row.fetchAll(db, sql: """
            SELECT t1.tag AS tag_a, t2.tag AS tag_b, COUNT(*) AS c
            FROM tags t1 JOIN tags t2 ON t1.note_id = t2.note_id AND t1.tag < t2.tag
            WHERE t1.tag IN (\(placeholders)) OR t2.tag IN (\(placeholders))
            GROUP BY t1.tag, t2.tag
            ORDER BY c DESC, tag_a ASC, tag_b ASC LIMIT ?
            """, arguments: StatementArguments(arguments))
        
        return rows.map { row in
            (row["tag_a"] as String, row["tag_b"] as String, row["c"] as Int)
        }
    }
    
    // MARK: - Private
}
