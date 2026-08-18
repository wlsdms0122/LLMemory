//
//  FetchLinkNeighborRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchLinkNeighborRowsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = (String, Double)
    let nid: String
    let siblingDiscount: Double

    // MARK: - Initializer
    init(nid: String, siblingDiscount: Double) {
        self.nid = nid
        self.siblingDiscount = siblingDiscount
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [NeighborRow] {

        return try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, n.summary, SUM(\(LinkRanking.weightSQL("l", siblingDiscount: siblingDiscount))) AS w
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
                title: row["title"],
                summary: row["summary"] as String?,
                value: row["w"] as Double? ?? 0
            )
        }
    }

    // MARK: - Private
}
