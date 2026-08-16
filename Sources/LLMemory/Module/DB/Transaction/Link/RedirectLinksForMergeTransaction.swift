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
            let rawKind: String = row["kind"]

            if NoteArtifacts.reconstructableLinkKinds.contains(rawKind) { continue }

            // A kind this binary does not recognise still has to be carried
            // over: every row of the merged-away note is deleted at the end,
            // so one left behind is one destroyed. It moves as a directed
            // edge, which is what an unclassified edge already behaved as.
            // index verify is where an unknown kind gets reported as one.
            let kind = LinkKind(rawValue: rawKind)
            let newSrc = (row["src"] as String) == fromId ? intoId : (row["src"] as String)
            let newDst = (row["dst"] as String) == fromId ? intoId : (row["dst"] as String)

            guard newSrc != newDst else { continue }

            let (source, destination) = kind?.endpoints(src: newSrc, dst: newDst) ?? (newSrc, newDst)

            let weight: Double = row["weight"]
            let createdAt: Int = row["created_at"]
            let lastActivatedAt: Int = row["last_activated_at"]
            let provenance: String? = row["provenance"]

            if kind?.isUndirected == true {
                try db.execute(sql: """
                    INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(src, dst, kind) DO UPDATE SET
                      weight = MIN(?, weight + excluded.weight),
                      last_activated_at = MAX(last_activated_at, excluded.last_activated_at)
                    """, arguments: [
                        source, destination, rawKind, min(weight, cap),
                        createdAt, lastActivatedAt, provenance, cap
                    ])
            } else {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        source, destination, rawKind, weight,
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
