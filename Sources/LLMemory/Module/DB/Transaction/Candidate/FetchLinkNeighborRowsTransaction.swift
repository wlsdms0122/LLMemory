//
//  FetchLinkNeighborRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchLinkNeighborRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let nid: String

    private let links = Links()

    private let policy = Policy()

    // MARK: - Initializer
    init(nid: String) {
        self.nid = nid
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [NeighborRow] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, n.summary, SUM(\(links.rankWeightSQL("l"))) AS w
            FROM (
              SELECT dst AS other, kind, weight FROM note_links WHERE src = ?
              UNION ALL
              SELECT src AS other, kind, weight FROM note_links WHERE dst = ?
            ) l
            JOIN notes n ON n.id = l.other
            WHERE \(policy.surface())
            GROUP BY n.id ORDER BY w DESC, n.id LIMIT 30
            """, arguments: [nid, nid]).map { row in
            NeighborRow(
                id: row["id"],
                title: row["title"],
                summary: row["summary"] as String?,
                value: row["w"] as Double? ?? 0
            )
        }
    }

    // MARK: - Private
}
