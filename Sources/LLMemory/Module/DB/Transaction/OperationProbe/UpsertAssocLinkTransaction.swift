//
//  UpsertAssocLinkTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct UpsertAssocLinkTransaction: GRDBTransaction {
    // MARK: - Property
    let src: String
    let dst: String
    let kind: String
    let weight: Double
    let now: Int
    let provenance: String?

    // MARK: - Initializer
    init(src: String, dst: String, kind: String, weight: Double, now: Int, provenance: String?) {
        self.src = src
        self.dst = dst
        self.kind = kind
        self.weight = weight
        self.now = now
        self.provenance = provenance
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at, provenance)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(src, dst, kind) DO UPDATE SET
              last_activated_at = excluded.last_activated_at
            """, arguments: [src, dst, kind, weight, now, now, provenance])
    }

    // MARK: - Private
}
