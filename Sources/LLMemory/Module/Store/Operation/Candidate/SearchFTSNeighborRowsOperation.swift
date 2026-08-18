//
//  SearchFTSNeighborRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SearchFTSNeighborRowsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = (String, String)
    let matchExpr: String
    let excludeId: String

    // MARK: - Initializer
    init(matchExpr: String, excludeId: String) {
        self.matchExpr = matchExpr
        self.excludeId = excludeId
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [NeighborRow] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, n.summary, MIN(rank) AS s
            FROM notes_fts f JOIN notes n ON n.id = f.id
            WHERE notes_fts MATCH ? AND n.id != ? AND \(Policy.surface())
            GROUP BY n.id
            ORDER BY s, n.id LIMIT 30
            """, arguments: [matchExpr, excludeId]).map { row in
            NeighborRow(
                id: row["id"],
                title: row["title"],
                summary: row["summary"] as String?,
                value: row["s"] as Double? ?? 0
            )
        }
    }

    // MARK: - Private
}
