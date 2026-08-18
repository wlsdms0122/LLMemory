//
//  SearchBM25NeighborRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SearchBM25NeighborRowsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = (String, String, Int)
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
    func execute(_ db: Database) throws -> [(id: String, score: Double)] {
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
