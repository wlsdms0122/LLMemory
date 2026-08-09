//
//  CandidateTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Candidate-domain transactions — row access for the restructuring detector.
// What counts as a candidate is Candidates' (Service tier) policy; these
// only fetch, returning neutral rows.
struct FetchSplitShapeRowsTransaction: GRDBReadTransaction {
    struct SplitShape {
        // MARK: - Property
        let id: String
        let axis: String
        let title: String
        let wordCount: Int
        let sectionCount: Int
        let tagCount: Int

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let minWords: Int
    let minSections: Int

    // MARK: - Initializer
    init(minWords: Int, minSections: Int) {
        self.minWords = minWords
        self.minSections = minSections
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [SplitShape] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.axis, n.title, n.word_count, n.section_count,
                   (SELECT COUNT(DISTINCT tag) FROM tags WHERE note_id = n.id) AS tag_count
            FROM notes n
            WHERE \(Policy.decayCandidate())
              AND n.word_count >= ?
              AND n.section_count >= ?
            ORDER BY n.word_count DESC, n.id ASC
            """, arguments: [minWords, minSections]).map { row in
            SplitShape(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                wordCount: row["word_count"] as Int? ?? 0,
                sectionCount: row["section_count"] as Int? ?? 0,
                tagCount: row["tag_count"] as Int? ?? 0
            )
        }
    }

    // MARK: - Private
}

struct FetchFlaggedRowsTransaction: GRDBReadTransaction {
    struct FlaggedNote {
        // MARK: - Property
        let noteId: String
        let reason: String?
        let createdAt: Int
        let axis: String
        let title: String
        let summary: String?

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let flag: String
    let limit: Int

    // MARK: - Initializer
    init(flag: String, limit: Int) {
        self.flag = flag
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [FlaggedNote] {
        try Row.fetchAll(db, sql: """
            SELECT r.note_id, r.reason, r.created_at, n.axis, n.title, n.summary
            FROM ripple_flags r
            JOIN notes n ON n.id = r.note_id
            WHERE r.flag = ? AND r.resolved_at IS NULL
              AND \(Policy.surface())
            ORDER BY r.created_at ASC, r.note_id ASC
            LIMIT ?
            """, arguments: [flag, limit]).map { row in
            FlaggedNote(
                noteId: row["note_id"],
                reason: row["reason"] as String?,
                createdAt: row["created_at"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?
            )
        }
    }

    // MARK: - Private
}

// One note's retrieval-facing header — the anchor row for neighbor scoring.
struct FetchNoteAnchorTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (axis: String, title: String, path: String)? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT id, axis, title, path FROM notes WHERE id = ?",
            arguments: [nid]
        ) else {
            return nil
        }

        return (row["axis"] as String, row["title"] as String, row["path"] as String)
    }

    // MARK: - Private
}

struct NeighborRow {
    // MARK: - Property
    let id: String
    let axis: String
    let title: String
    let summary: String?
    let value: Double

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct SearchFTSNeighborRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let matchExpr: String
    let excludeId: String

    // MARK: - Initializer
    init(matchExpr: String, excludeId: String) {
        self.matchExpr = matchExpr
        self.excludeId = excludeId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [NeighborRow] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.axis, n.title, n.summary, MIN(rank) AS s
            FROM notes_fts f JOIN notes n ON n.id = f.id
            WHERE notes_fts MATCH ? AND n.id != ? AND \(Policy.surface())
            GROUP BY n.id
            ORDER BY s, n.id LIMIT 30
            """, arguments: [matchExpr, excludeId]).map { row in
            NeighborRow(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?,
                value: row["s"] as Double? ?? 0
            )
        }
    }

    // MARK: - Private
}

struct FetchNoteEntitySetTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(
            db,
            sql: "SELECT entity FROM entity_index WHERE note_id = ?",
            arguments: [nid]
        ))
    }

    // MARK: - Private
}

struct FetchEntityOverlapRowsTransaction: GRDBReadTransaction {
    struct EntityOverlap {
        // MARK: - Property
        let id: String
        let axis: String
        let title: String
        let summary: String?
        let intersection: Int
        let size: Int

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [EntityOverlap] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.axis, n.title, n.summary,
                   (SELECT COUNT(*) FROM entity_index e1
                     JOIN entity_index e2 ON e1.entity = e2.entity
                     WHERE e1.note_id = ? AND e2.note_id = n.id) AS inter,
                   (SELECT COUNT(*) FROM entity_index WHERE note_id = n.id) AS sz
            FROM notes n
            WHERE n.id != ? AND \(Policy.surface())
            """, arguments: [nid, nid]).map { row in
            EntityOverlap(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?,
                intersection: row["inter"] as Int? ?? 0,
                size: row["sz"] as Int? ?? 0
            )
        }
    }

    // MARK: - Private
}

struct FetchLinkNeighborRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [NeighborRow] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.axis, n.title, n.summary, SUM(\(Links.rankWeightSQL("l"))) AS w
            FROM (
              SELECT dst AS other, kind, weight FROM note_links WHERE src = ?
              UNION ALL
              SELECT src AS other, kind, weight FROM note_links WHERE dst = ?
            ) l
            JOIN notes n ON n.id = l.other
            WHERE \(Policy.surface())
            GROUP BY n.id ORDER BY w DESC, n.id LIMIT 30
            """, arguments: [nid, nid]).map { row in
            NeighborRow(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?,
                value: row["w"] as Double? ?? 0
            )
        }
    }

    // MARK: - Private
}

// Cluster substrate — surfaced, forget-exempt link and entity co-mention
// edges.
struct FetchClusterEdgesTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(String, String)] {
        var edges: [(String, String)] = []

        for row in try Row.fetchAll(db, sql: """
            SELECT src, dst FROM note_links nl
            JOIN notes a ON a.id = nl.src
            JOIN notes b ON b.id = nl.dst
            WHERE \(Policy.all(Policy.surface("a"), Policy.forgetExempt("a")))
              AND \(Policy.all(Policy.surface("b"), Policy.forgetExempt("b")))
            """) {
            edges.append((row["src"], row["dst"]))
        }

        for row in try Row.fetchAll(db, sql: """
            SELECT e1.note_id AS a, e2.note_id AS b
            FROM entity_index e1 JOIN entity_index e2
              ON e1.entity = e2.entity AND e1.note_id < e2.note_id
            JOIN notes na ON na.id = e1.note_id
            JOIN notes nb ON nb.id = e2.note_id
            WHERE \(Policy.all(Policy.surface("na"), Policy.forgetExempt("na")))
              AND \(Policy.all(Policy.surface("nb"), Policy.forgetExempt("nb")))
            GROUP BY e1.note_id, e2.note_id
            """) {
            edges.append((row["a"], row["b"]))
        }

        return edges
    }

    // MARK: - Private
}

struct MetaRow {
    // MARK: - Property
    let id: String
    let axis: String
    let title: String
    let summary: String?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct FetchClusterMemberRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let ids: [String]

    // MARK: - Initializer
    init(ids: [String]) {
        self.ids = ids
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [MetaRow] {
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")

        return try Row.fetchAll(
            db,
            sql: "SELECT id, axis, title, summary FROM notes WHERE id IN (\(placeholders)) ORDER BY id",
            arguments: StatementArguments(ids)
        ).map { row in
            MetaRow(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?
            )
        }
    }

    // MARK: - Private
}

struct FetchSurfaceLinkPairsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(src: String, dst: String)] {
        try Row.fetchAll(db, sql: """
            SELECT l.src, l.dst FROM note_links l
            JOIN notes ns ON ns.id = l.src AND \(Policy.surface("ns"))
            JOIN notes nd ON nd.id = l.dst AND \(Policy.surface("nd"))
            """).map { row in (src: row["src"] as String, dst: row["dst"] as String) }
    }

    // MARK: - Private
}

struct FetchSurfaceMetaRowsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [MetaRow] {
        try Row.fetchAll(
            db,
            sql: "SELECT id, axis, title, summary FROM notes WHERE \(Policy.all(Policy.surface(""), Policy.notEager("")))"
        ).map { row in
            MetaRow(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?
            )
        }
    }

    // MARK: - Private
}

struct SearchBM25NeighborRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let matchExpr: String
    let excludeId: String
    let limit: Int

    // MARK: - Initializer
    init(matchExpr: String, excludeId: String, limit: Int) {
        self.matchExpr = matchExpr
        self.excludeId = excludeId
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [(id: String, score: Double)] {
        try Row.fetchAll(db, sql: """
            SELECT n.id AS id, MIN(rank) AS s
            FROM notes_fts f JOIN notes n ON n.id = f.id
            WHERE notes_fts MATCH ? AND n.id != ? AND \(Policy.all(Policy.surface(), Policy.notEager()))
            GROUP BY n.id
            ORDER BY s, n.id LIMIT ?
            """, arguments: [matchExpr, excludeId, limit]).map { row in
            (id: row["id"] as String, score: row["s"] as Double? ?? 0)
        }
    }

    // MARK: - Private
}

struct FetchSurfaceNoteRowsTransaction: GRDBReadTransaction {
    struct SurfaceNote {
        // MARK: - Property
        let id: String
        let axis: String
        let title: String
        let summary: String?
        let path: String

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [SurfaceNote] {
        try Row.fetchAll(db, sql: """
            SELECT id, axis, title, summary, path FROM notes
            WHERE \(Policy.all(Policy.surface(""), Policy.forgetExempt("")))
            ORDER BY id
            """).map { row in
            SurfaceNote(
                id: row["id"],
                axis: row["axis"],
                title: row["title"],
                summary: row["summary"] as String?,
                path: row["path"]
            )
        }
    }

    // MARK: - Private
}
