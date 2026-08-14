//
//  ListNoteRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ListNoteRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let filter: NoteListFilter

    private let search = Search()

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

        let (tagClause, tagArguments) = try search.tagClause(db, tags: filter.tags)

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
