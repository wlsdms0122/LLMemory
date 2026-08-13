//
//  ReadTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

// Read-surface DTOs and the catalog/list/entity/history transactions.
// Models are flat top-level types; a domain prefix disambiguates where the
// bare name could mean something else in this module (NoteListRow vs the
// genome rows, NoteView vs the NoteRecord table row). A name that
// stands alone (TocEntry, BudgetCut) stays bare — same convention as the
// service results.
struct CatalogNote: Sendable {
    // MARK: - Property
    let id: String
    let path: String
    let title: String
    let summary: String?
    let priority: String
    let hitCount: Int
    let createdAt: Int
    let editedAt: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct NoteListRow: Encodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case id, title, summary, priority, stale
        case sourceStale = "source_stale"
        case createdAt = "created_at"
        case editedAt = "edited_at"
    }

    // MARK: - Property
    public let id: String
    public let title: String
    public let summary: String?
    public let priority: String
    public let stale: Bool
    public let sourceStale: Bool
    public let createdAt: Int
    public let editedAt: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

// A custom frontmatter field to match on: the key alone means "has it",
// key + value means "has it with exactly this value".
public struct NoteFieldFilter: Sendable {
    // MARK: - Property
    public let key: String
    public let value: String?

    // MARK: - Initializer
    public init(key: String, value: String?) {
        self.key = key
        self.value = value
    }

    // MARK: - Public
    // MARK: - Private
}

struct NoteListFilter {
    // MARK: - Property
    var priority: String?
    var tags: [String]
    var fields: [NoteFieldFilter]
    var stale: Bool
    var sourceStale: Bool
    var limit: Int?

    // MARK: - Initializer
    init(
        priority: String? = nil,
        tags: [String] = [],
        fields: [NoteFieldFilter] = [],
        stale: Bool = false,
        sourceStale: Bool = false,
        limit: Int? = nil
    ) {
        self.priority = priority
        self.tags = tags
        self.fields = fields
        self.stale = stale
        self.sourceStale = sourceStale
        self.limit = limit
    }

    // MARK: - Public
    // MARK: - Private
}

public struct NoteHistoryEvent: Encodable, Sendable {
    // MARK: - Property
    public let kind: String
    public let reason: String?
    public let at: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct NoteFrontmatter: Encodable, Sendable {
    // MARK: - Property
    private let doc: FrontmatterDoc

    // MARK: - Initializer
    init(_ doc: FrontmatterDoc) {
        self.doc = doc
    }

    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        try doc.encode(to: encoder)
    }

    // MARK: - Private
}

public struct NoteView: Sendable {
    // MARK: - Property
    public let id, path: String
    public let frontmatter: NoteFrontmatter
    public let body: String
    public let hitCount, createdAt, editedAt: Int
    public let priority: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct SectionSlice: Sendable {
    // MARK: - Property
    public let path: String
    public let text: String

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct TocEntry: Sendable {
    // MARK: - Property
    public let path: String
    public let words: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct BudgetCut: Sendable {
    // MARK: - Property
    public let shown: String
    public let shownSections: [TocEntry]
    public let omitted: [TocEntry]
    public let truncatedWithin: String?
    public let shownWords: Int
    public let totalWords: Int

    public var truncated: Bool { !omitted.isEmpty || truncatedWithin != nil }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

public struct StructureResult: Sendable {
    // MARK: - Property
    public let tree: [TreeRow]
    public let distribution: LinkDistribution
    public let prefixStats: PrefixStats?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct FetchNoteCatalogTransaction: GRDBReadTransaction {
    // MARK: - Property
    let ids: [String]

    // MARK: - Initializer
    init(ids: [String]) {
        self.ids = ids
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: CatalogNote] {
        guard !ids.isEmpty else { return [:] }

        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let rows = try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, n.summary, n.priority,
                   COALESCE(u.hit_count, 0) AS hit_count,
                   COALESCE(u.created_at, 0) AS created_at, n.edited_at
            FROM notes n LEFT JOIN note_usage u ON u.note_id = n.id
            WHERE n.id IN (\(placeholders))
            """, arguments: StatementArguments(ids))
        var catalog: [String: CatalogNote] = [:]

        for row in rows {
            catalog[row["id"] as String] = CatalogNote(
                id: row["id"],
                path: Paths.relativeFile(forId: row["id"] as String),
                title: row["title"],
                summary: row["summary"] as String?,
                priority: row["priority"],
                hitCount: row["hit_count"] as Int? ?? 0,
                createdAt: row["created_at"] as Int? ?? 0,
                editedAt: row["edited_at"] as Int? ?? 0
            )
        }

        return catalog
    }

    // MARK: - Private
}

struct ListNoteRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let filter: NoteListFilter

    // MARK: - Initializer
    init(_ filter: NoteListFilter) {
        self.filter = filter
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [NoteListRow] {
        var clauses: [String] = []
        var arguments: [DatabaseValueConvertible?] = []

        if let priority = filter.priority {
            clauses.append("n.priority = ?")
            arguments.append(priority)
        }

        let (tagClause, tagArguments) = try Search.tagClause(db, tags: filter.tags)

        if !tagClause.isEmpty {
            clauses.append(tagClause)
            arguments.append(contentsOf: tagArguments)
        }

        for field in filter.fields {
            var clause = "EXISTS (SELECT 1 FROM note_extra x"
                + " WHERE x.note_id = n.id AND x.key = ?"

            arguments.append(field.key)

            if let value = field.value {
                clause += " AND x.value = ?"
                arguments.append(value)
            }

            clauses.append(clause + ")")
        }

        if filter.stale { clauses.append("n.stale = 1") }
        if filter.sourceStale { clauses.append("s.source_stale = 1") }

        var sql = """
            SELECT n.id, n.title, n.summary, n.priority, n.stale,
                   COALESCE(s.source_stale, 0) AS source_stale,
                   COALESCE(u.created_at, 0) AS created_at, n.edited_at
            FROM notes n LEFT JOIN note_source s ON s.note_id = n.id
                         LEFT JOIN note_usage u ON u.note_id = n.id
            \(clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))")
            ORDER BY n.id
            """

        if let limit = filter.limit { sql += " LIMIT \(limit)" }

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            .map { row in
                NoteListRow(
                    id: row["id"],
                    title: row["title"],
                    summary: row["summary"] as String?,
                    priority: row["priority"],
                    stale: (row["stale"] as Int? ?? 0) != 0,
                    sourceStale: (row["source_stale"] as Int? ?? 0) != 0,
                    createdAt: row["created_at"] as Int? ?? 0,
                    editedAt: row["edited_at"] as Int? ?? 0
                )
            }
    }

    // MARK: - Private
}

struct LookupEntitiesTransaction: GRDBReadTransaction {
    // MARK: - Property
    let name: String?
    let limit: Int

    // MARK: - Initializer
    init(name: String?, limit: Int) {
        self.name = name
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [EntityHit] {
        let sql: String
        let arguments: [DatabaseValueConvertible?]

        if let name {
            sql = """
                SELECT ei.entity, ei.note_id, n.title, n.summary, ei.last_seen_at, ei.hit_count
                FROM entity_index ei LEFT JOIN notes n ON n.id = ei.note_id
                WHERE ei.entity = ? ORDER BY ei.last_seen_at DESC, ei.note_id ASC LIMIT ?
                """
            arguments = [name, limit]
        } else {
            sql = """
                SELECT ei.entity, ei.note_id, n.title, n.summary, ei.last_seen_at, ei.hit_count
                FROM entity_index ei LEFT JOIN notes n ON n.id = ei.note_id
                ORDER BY ei.last_seen_at DESC, ei.entity ASC, ei.note_id ASC LIMIT ?
                """
            arguments = [limit]
        }

        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            .map { row in
                EntityHit(
                    entity: row["entity"],
                    noteId: row["note_id"],
                    lastSeenAt: row["last_seen_at"] as Int? ?? 0,
                    hitCount: row["hit_count"] as Int? ?? 0,
                    title: row["title"] as String?,
                    summary: row["summary"] as String?
                )
            }
    }

    // MARK: - Private
}

struct FetchNoteHistoryTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String
    let limit: Int

    // MARK: - Initializer
    init(noteId: String, limit: Int) {
        self.noteId = noteId
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [NoteHistoryEvent] {
        try Row.fetchAll(db, sql: """
            SELECT kind, reason, created_at FROM note_lifecycle_events
            WHERE note_id = ? ORDER BY id DESC LIMIT ?
            """, arguments: [noteId, limit])
            .map { row in
                NoteHistoryEvent(
                    kind: row["kind"],
                    reason: row["reason"] as String?,
                    at: row["created_at"]
                )
            }
    }

    // MARK: - Private
}
