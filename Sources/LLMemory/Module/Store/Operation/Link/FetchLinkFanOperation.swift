//
//  FetchLinkFanOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchLinkFanOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = String
    let fromId: String

    // MARK: - Initializer
    init(fromId: String) {
        self.fromId = fromId
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> (outEdges: [LinkEdge], inEdges: [LinkEdge]) {
        let outboundRows = try Row.fetchAll(db, sql: """
            SELECT dst, kind, weight, created_at, last_activated_at, provenance
            FROM note_links WHERE src = ?
            """, arguments: [fromId])
        let inboundRows = try Row.fetchAll(db, sql: """
            SELECT src, kind, weight, created_at, last_activated_at, provenance
            FROM note_links WHERE dst = ?
            """, arguments: [fromId])
        let outEdges: [LinkEdge] = outboundRows.map { row in
            LinkEdge(
                other: row["dst"],
                kind: row["kind"],
                weight: row["weight"],
                createdAt: row["created_at"],
                lastActivatedAt: row["last_activated_at"],
                provenance: row["provenance"]
            )
        }
        let inEdges: [LinkEdge] = inboundRows.map { row in
            LinkEdge(
                other: row["src"],
                kind: row["kind"],
                weight: row["weight"],
                createdAt: row["created_at"],
                lastActivatedAt: row["last_activated_at"],
                provenance: row["provenance"]
            )
        }

        return (outEdges, inEdges)
    }

    // MARK: - Private
}
