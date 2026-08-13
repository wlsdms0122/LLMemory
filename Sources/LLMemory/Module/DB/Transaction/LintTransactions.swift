//
//  LintTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Lint-domain transactions — row access for the note inspector. What counts
// as a defect is LintService's rule catalog; these only fetch.
struct FetchLintCorpusIndexTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> LintCorpusIndex {
        var aliases: [String: String] = [:]

        for row in try Row.fetchAll(db, sql: "SELECT alias, canonical FROM tag_aliases") {
            aliases[row["alias"]] = row["canonical"]
        }

        return LintCorpusIndex(
            ids: Set(try String.fetchAll(db, sql: "SELECT id FROM notes")),
            tagAliases: aliases
        )
    }

    // MARK: - Private
}

struct FetchNoteShapeTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (words: Int, sections: Int) {
        let row = try Row.fetchOne(
            db,
            sql: "SELECT word_count, section_count FROM notes WHERE id = ?",
            arguments: [nid]
        )

        return (
            row?["word_count"] as Int? ?? 0,
            row?["section_count"] as Int? ?? 0
        )
    }

    // MARK: - Private
}

struct CountActiveRetrievalTermsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM note_retrieval_terms WHERE note_id = ? AND status = 'active'",
            arguments: [noteId]
        ) ?? 0
    }

    // MARK: - Private
}

struct FragmentationRow {
    // MARK: - Property
    let nid: String
    let linkN: Int
    let entN: Int
    let tagN: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct FetchFragmentationRowsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [FragmentationRow] {
        try Row.fetchAll(db, sql: """
            SELECT n.id,
                   (SELECT COUNT(*) FROM note_links l
                      JOIN notes o ON o.id = CASE WHEN l.src = n.id THEN l.dst ELSE l.src END
                     WHERE (l.src = n.id OR l.dst = n.id)) AS link_n,
                   (SELECT COUNT(*) FROM entity_index WHERE note_id = n.id) AS ent_n,
                   (SELECT COUNT(*) FROM tags WHERE note_id = n.id) AS tag_n
            FROM notes n
            WHERE \(Policy.notEager())
            """).map { row in
            FragmentationRow(
                nid: row["id"],
                linkN: row["link_n"] as Int? ?? 0,
                entN: row["ent_n"] as Int? ?? 0,
                tagN: row["tag_n"] as Int? ?? 0
            )
        }
    }

    // MARK: - Private
}

struct FetchTagUsageTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(tag: String, c: Int)] {
        try Row.fetchAll(db, sql: "SELECT tag, COUNT(*) c FROM tags GROUP BY tag")
            .map { row in (row["tag"], row["c"] as Int? ?? 0) }
    }

    // MARK: - Private
}

struct FetchFamilyGraphTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> (notes: [String], siblingLinks: [(src: String, dst: String)]) {
        let notes = try String.fetchAll(db, sql: "SELECT id FROM notes")
        let links = try Row.fetchAll(
            db,
            sql: "SELECT src, dst FROM note_links WHERE kind = ?",
            arguments: [Links.kindSibling]
        )
            .map { row in (src: row["src"] as String, dst: row["dst"] as String) }

        return (notes, links)
    }

    // MARK: - Private
}

struct FetchDeliberateNeighborsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String

    // MARK: - Initializer
    init(noteId: String) {
        self.noteId = noteId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        let deliberate = Links.deleteBlockingKinds
        let kindPlaceholders = Array(repeating: "?", count: deliberate.count)
            .joined(separator: ",")
        let arguments: [DatabaseValueConvertible?] = [noteId, noteId, noteId]
            + (Array(deliberate) as [DatabaseValueConvertible?])

        return try String.fetchAll(db, sql: """
            SELECT CASE WHEN src = ? THEN dst ELSE src END AS other FROM note_links
            WHERE (src = ? OR dst = ?) AND kind IN (\(kindPlaceholders))
            """, arguments: StatementArguments(arguments))
    }

    // MARK: - Private
}
