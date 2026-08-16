//
//  FetchLinkNeighborsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchLinkNeighborsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let noteId: String
    let minWeight: Double?
    let limit: Int
    let kind: String?

    // MARK: - Initializer
    init(noteId: String, minWeight: Double? = nil, limit: Int = 5, kind: String? = nil) {
        self.noteId = noteId
        self.minWeight = minWeight
        self.limit = limit
        self.kind = kind
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [LinkNeighbor] {
        let floor = minWeight ?? Genes.double("links.neighbor_floor")
        var sql = """
            SELECT n.id, n.title, n.summary, l.kind, l.weight,
                   \(LinkRanking.weightSQL("l")) AS rank_w
            FROM note_links l
            JOIN notes n ON n.id = CASE WHEN l.src = ? THEN l.dst ELSE l.src END
            WHERE (l.src = ? OR l.dst = ?) AND l.weight >= ?
              AND \(Policy.surface())
            """
        var arguments: [DatabaseValueConvertible?] = [noteId, noteId, noteId, floor]

        if let kind {
            sql += " AND l.kind = ?"
            arguments.append(kind)
        }

        sql += " ORDER BY rank_w DESC, n.id LIMIT ?"
        arguments.append(limit)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))

        return rows.map { row in
            LinkNeighbor(
                id: row["id"],
                title: row["title"],
                summary: row["summary"] as String?,
                path: Paths.relativeFile(forId: row["id"] as String),
                kind: row["kind"],
                weight: row["weight"]
            )
        }
    }

    // MARK: - Private
}
