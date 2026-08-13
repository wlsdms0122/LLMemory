//
//  VocabTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Vocabulary transactions — axes, tag vocab, and tag aliases.
struct EnsureAxisTransaction: GRDBTransaction {
    // MARK: - Property
    let axis: String
    let now: Int?

    // MARK: - Initializer
    init(axis: String, now: Int? = nil) {
        self.axis = axis
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)

        try db.execute(
            sql: "INSERT OR IGNORE INTO axes (axis, created_at) VALUES (?, ?)",
            arguments: [axis, timestamp]
        )
    }

    // MARK: - Private
}

struct EnsureTagTransaction: GRDBTransaction {
    // MARK: - Property
    let tag: String
    let now: Int?

    // MARK: - Initializer
    init(tag: String, now: Int? = nil) {
        self.tag = tag
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let timestamp = now ?? Int(Date().timeIntervalSince1970)

        try db.execute(
            sql: "INSERT OR IGNORE INTO tag_vocab (tag, created_at) VALUES (?, ?)",
            arguments: [tag, timestamp]
        )
    }

    // MARK: - Private
}

struct CanonicalizeTagTransaction: GRDBReadTransaction {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> String {
        let canonical = try String.fetchOne(
            db,
            sql: "SELECT canonical FROM tag_aliases WHERE alias = ?",
            arguments: [tag]
        )

        return canonical ?? tag
    }

    // MARK: - Private
}

struct AxisExistsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let axis: String

    // MARK: - Initializer
    init(axis: String) {
        self.axis = axis
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT 1 FROM axes WHERE axis = ?", arguments: [axis]) != nil
    }

    // MARK: - Private
}

struct FetchAxisCreatedAtTransaction: GRDBReadTransaction {
    // MARK: - Property
    let axis: String

    // MARK: - Initializer
    init(axis: String) {
        self.axis = axis
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int? {
        try Int.fetchOne(
            db,
            sql: "SELECT created_at FROM axes WHERE axis = ?",
            arguments: [axis]
        )
    }

    // MARK: - Private
}

struct CreateAxisTransaction: GRDBTransaction {
    // MARK: - Property
    let axis: String
    let createdAt: Int

    // MARK: - Initializer
    init(axis: String, createdAt: Int) {
        self.axis = axis
        self.createdAt = createdAt
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(
            sql: "INSERT INTO axes (axis, created_at) VALUES (?, ?)",
            arguments: [axis, createdAt]
        )
    }

    // MARK: - Private
}

struct DeleteAxisTransaction: GRDBTransaction {
    // MARK: - Property
    let axis: String

    // MARK: - Initializer
    init(axis: String) {
        self.axis = axis
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM axes WHERE axis = ?", arguments: [axis])
    }

    // MARK: - Private
}

struct PruneEmptyAxesTransaction: GRDBTransaction {
    // MARK: - Property
    let protected: Set<String>

    // MARK: - Initializer
    init(protected: Set<String> = []) {
        self.protected = protected
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
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

    // MARK: - Private
}

struct RetireTagTransaction: GRDBTransaction {
    // MARK: - Property
    let tag: String
    let successor: String

    // MARK: - Initializer
    init(tag: String, successor: String) {
        self.tag = tag
        self.successor = successor
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
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

    // MARK: - Private
}

struct TagVocabExistsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM tag_vocab WHERE tag = ?",
            arguments: [tag]
        ) != nil
    }

    // MARK: - Private
}

struct TagInUseTransaction: GRDBReadTransaction {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM tags WHERE tag = ? LIMIT 1",
            arguments: [tag]
        ) != nil
    }

    // MARK: - Private
}

struct PruneUnusedVocabTagsTransaction: GRDBTransaction {
    // MARK: - Property
    let protected: Set<String>

    // MARK: - Initializer
    init(protected: Set<String> = []) {
        self.protected = protected
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
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

    // MARK: - Private
}

struct AddTagAliasTransaction: GRDBTransaction {
    // MARK: - Property
    let alias: String
    let canonical: String
    let now: Int

    // MARK: - Initializer
    init(alias: String, canonical: String, now: Int) {
        self.alias = alias
        self.canonical = canonical
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO tag_aliases (alias, canonical, created_at) VALUES (?, ?, ?)",
            arguments: [alias, canonical, now]
        )
    }

    // MARK: - Private
}

// A spelling that becomes a canonical tag cannot stay an alias — reprojection
// canonicalises frontmatter tags through tag_aliases, so a stale claim would
// silently rewrite the new tag back to its old canonical.
struct DropTagAliasClaimTransaction: GRDBTransaction {
    // MARK: - Property
    let alias: String

    // MARK: - Initializer
    init(alias: String) {
        self.alias = alias
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM tag_aliases WHERE alias = ?", arguments: [alias])
    }

    // MARK: - Private
}

struct ClearNoteTagsTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM tags WHERE note_id = ?", arguments: [noteId])
    }

    // MARK: - Private
}

struct ReplaceNoteTagTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let fromTag: String
    let toTag: String

    // MARK: - Initializer
    init(noteId: String, fromTag: String, toTag: String) {
        self.noteId = noteId
        self.fromTag = fromTag
        self.toTag = toTag
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(
            sql: "DELETE FROM tags WHERE note_id = ? AND tag = ?",
            arguments: [noteId, fromTag]
        )
        try db.execute(
            sql: "INSERT OR IGNORE INTO tags (note_id, tag) VALUES (?, ?)",
            arguments: [noteId, toTag]
        )
    }

    // MARK: - Private
}

struct FetchNotesWithTagTransaction: GRDBReadTransaction {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT DISTINCT note_id FROM tags WHERE tag = ?",
            arguments: [tag]
        )
    }

    // MARK: - Private
}

struct FetchPathsWithTagTransaction: GRDBReadTransaction {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT DISTINCT n.path FROM notes n JOIN tags t ON t.note_id = n.id WHERE t.tag = ?
            """, arguments: [tag])
    }

    // MARK: - Private
}

struct FetchTagCooccurrenceTransaction: GRDBReadTransaction {
    // MARK: - Property
    let tags: [String]
    let limit: Int

    // MARK: - Initializer
    init(tags: [String], limit: Int = 15) {
        self.tags = tags
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(tagA: String, tagB: String, count: Int)] {
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
