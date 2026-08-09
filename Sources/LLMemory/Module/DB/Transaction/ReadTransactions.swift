//
//  ReadTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

// Read-surface DTOs and the catalog/list/entity/history transactions.
public enum Reads {
    struct CatalogNote: Sendable {
        // MARK: - Property
        let id: String
        let path: String
        let axis: String
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
    
    public struct ListRow: Encodable, Sendable {
        enum CodingKeys: String, CodingKey {
            case id, axis, title, summary, priority, stale
            case sourceStale = "source_stale"
            case createdAt = "created_at"
            case editedAt = "edited_at"
        }
        
        // MARK: - Property
        public let id: String
        public let axis: String
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
    
    struct ListFilter {
        // MARK: - Property
        var priority: String?
        var axis: String?
        var stale: Bool
        var sourceStale: Bool
        var limit: Int?
        
        // MARK: - Initializer
        init(
            priority: String? = nil,
            axis: String? = nil,
            stale: Bool = false,
            sourceStale: Bool = false,
            limit: Int? = nil
        ) {
            self.priority = priority
            self.axis = axis
            self.stale = stale
            self.sourceStale = sourceStale
            self.limit = limit
        }
        
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct EntityHit: Encodable, Sendable {
        enum CodingKeys: String, CodingKey {
            case entity, axis, summary
            case noteId = "note_id"
            case lastSeenAt = "last_seen_at"
            case hitCount = "hit_count"
        }
        
        // MARK: - Property
        public let entity: String
        public let noteId: String
        public let axis: String?
        public let summary: String?
        public let lastSeenAt: Int
        public let hitCount: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    public struct HistoryEvent: Encodable, Sendable {
        // MARK: - Property
        public let kind: String
        public let reason: String?
        public let at: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public

    

    

    

    
    // MARK: - Private
}

public extension Reads {
    struct NoteFrontmatter: Encodable, Sendable {
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
    
    struct GetNote: Sendable {
        // MARK: - Property
        public let id, axis, path: String
        public let frontmatter: NoteFrontmatter
        public let body: String
        public let hitCount, createdAt, editedAt: Int
        public let priority: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct SectionSlice: Sendable {
        // MARK: - Property
        public let path: String
        public let text: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct TocEntry: Sendable {
        // MARK: - Property
        public let path: String
        public let words: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct BudgetCut: Sendable {
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
    
    struct StructureResult: Sendable {
        // MARK: - Property
        public let axes: [(axis: String, description: String?, count: Int)]
        public let distribution: Links.Distribution
        public let axisStats: AxisStats?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
}

struct FetchNoteCatalogTransaction: GRDBReadTransaction {
    // MARK: - Property
    let ids: [String]

    // MARK: - Initializer
    init(ids: [String]) {
        self.ids = ids
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: Reads.CatalogNote] {
        guard !ids.isEmpty else { return [:] }
        
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let rows = try Row.fetchAll(db, sql: """
            SELECT n.id, n.path, n.axis, n.title, n.summary, n.priority,
                   COALESCE(u.hit_count, 0) AS hit_count,
                   COALESCE(u.created_at, 0) AS created_at, n.edited_at
            FROM notes n LEFT JOIN note_usage u ON u.note_id = n.id
            WHERE n.id IN (\(placeholders))
            """, arguments: StatementArguments(ids))
        var catalog: [String: Reads.CatalogNote] = [:]
        
        for row in rows {
            catalog[row["id"] as String] = Reads.CatalogNote(
                id: row["id"],
                path: row["path"],
                axis: row["axis"],
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
    let filter: Reads.ListFilter

    // MARK: - Initializer
    init(_ filter: Reads.ListFilter) {
        self.filter = filter
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Reads.ListRow] {
        var clauses: [String] = []
        var arguments: [DatabaseValueConvertible?] = []
        
        if let priority = filter.priority {
            clauses.append("n.priority = ?")
            arguments.append(priority)
        }
        
        if let axis = filter.axis {
            clauses.append("n.axis = ?")
            arguments.append(axis)
        }
        
        if filter.stale { clauses.append("n.stale = 1") }
        if filter.sourceStale { clauses.append("s.source_stale = 1") }
        
        var sql = """
            SELECT n.id, n.axis, n.title, n.summary, n.priority, n.stale,
                   COALESCE(s.source_stale, 0) AS source_stale,
                   COALESCE(u.created_at, 0) AS created_at, n.edited_at
            FROM notes n LEFT JOIN note_source s ON s.note_id = n.id
                         LEFT JOIN note_usage u ON u.note_id = n.id
            \(clauses.isEmpty ? "" : "WHERE \(clauses.joined(separator: " AND "))")
            ORDER BY n.axis, n.id
            """
        
        if let limit = filter.limit { sql += " LIMIT \(limit)" }
        
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            .map { row in
                Reads.ListRow(
                    id: row["id"],
                    axis: row["axis"],
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
    func perform(_ db: Database) throws -> [Reads.EntityHit] {
        let sql: String
        let arguments: [DatabaseValueConvertible?]
        
        if let name {
            sql = """
                SELECT ei.entity, ei.note_id, n.axis, n.summary, ei.last_seen_at, ei.hit_count
                FROM entity_index ei LEFT JOIN notes n ON n.id = ei.note_id
                WHERE ei.entity = ? ORDER BY ei.last_seen_at DESC, ei.note_id ASC LIMIT ?
                """
            arguments = [name, limit]
        } else {
            sql = """
                SELECT ei.entity, ei.note_id, n.axis, n.summary, ei.last_seen_at, ei.hit_count
                FROM entity_index ei LEFT JOIN notes n ON n.id = ei.note_id
                ORDER BY ei.last_seen_at DESC, ei.entity ASC, ei.note_id ASC LIMIT ?
                """
            arguments = [limit]
        }
        
        return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            .map { row in
                Reads.EntityHit(
                    entity: row["entity"],
                    noteId: row["note_id"],
                    axis: row["axis"] as String?,
                    summary: row["summary"] as String?,
                    lastSeenAt: row["last_seen_at"] as Int? ?? 0,
                    hitCount: row["hit_count"] as Int? ?? 0
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
    func perform(_ db: Database) throws -> [Reads.HistoryEvent] {
        try Row.fetchAll(db, sql: """
            SELECT kind, reason, created_at FROM note_lifecycle_events
            WHERE note_id = ? ORDER BY id DESC LIMIT ?
            """, arguments: [noteId, limit])
            .map { row in
                Reads.HistoryEvent(
                    kind: row["kind"],
                    reason: row["reason"] as String?,
                    at: row["created_at"]
                )
            }
    }

    // MARK: - Private
}
