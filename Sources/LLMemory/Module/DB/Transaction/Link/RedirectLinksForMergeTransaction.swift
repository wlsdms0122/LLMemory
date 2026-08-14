//
//  RedirectLinksForMergeTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RedirectLinksForMergeTransaction: GRDBTransaction {
    // MARK: - Property
    let fromId: String
    let intoId: String

    // MARK: - Initializer
    init(fromId: String, intoId: String) {
        self.fromId = fromId
        self.intoId = intoId
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let cap = 1.0
        let rows = try Row.fetchAll(db, sql: """
            SELECT src, dst, kind, weight, created_at, last_activated_at, provenance
            FROM note_links WHERE src = ? OR dst = ?
            """, arguments: [fromId, fromId])

        for row in rows {
            let kind: String = row["kind"]

            if NoteArtifacts.reconstructableLinkKinds.contains(kind) { continue }

            let newSrc = (row["src"] as String) == fromId ? intoId : (row["src"] as String)
            let newDst = (row["dst"] as String) == fromId ? intoId : (row["dst"] as String)

            guard let (source, destination) = Links.normalize(
                src: newSrc,
                dst: newDst,
                kind: kind
            ) else {
                continue
            }

            let weight: Double = row["weight"]
            let createdAt: Int = row["created_at"]
            let lastActivatedAt: Int = row["last_activated_at"]
            let provenance: String? = row["provenance"]

            if Links.undirectedKinds.contains(kind) {
                try db.execute(sql: """
                    INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(src, dst, kind) DO UPDATE SET
                      weight = MIN(?, weight + excluded.weight),
                      last_activated_at = MAX(last_activated_at, excluded.last_activated_at)
                    """, arguments: [
                        source, destination, kind, min(weight, cap),
                        createdAt, lastActivatedAt, provenance, cap
                    ])
            } else {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        source, destination, kind, weight,
                        createdAt, lastActivatedAt, provenance
                    ])
            }
        }

        try db.execute(
            sql: "DELETE FROM note_links WHERE src = ? OR dst = ?",
            arguments: [fromId, fromId]
        )
    }

    // MARK: - Private
}
