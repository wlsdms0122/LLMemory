//
//  AddLinkOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct AddLinkOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, String, String, Double, Int, Int, String?)
    let src: String
    let dst: String
    let kind: String
    let weight: Double
    let createdAt: Int
    let lastActivatedAt: Int
    let provenance: String?

    // MARK: - Initializer
    init(
        src: String,
        dst: String,
        kind: String,
        weight: Double,
        createdAt: Int,
        lastActivatedAt: Int,
        provenance: String? = nil
    ) {
        self.src = src
        self.dst = dst
        self.kind = kind
        self.weight = weight
        self.createdAt = createdAt
        self.lastActivatedAt = lastActivatedAt
        self.provenance = provenance
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        if src == dst { return }

        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links
              (src, dst, kind, weight, created_at, last_activated_at, provenance)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [src, dst, kind, weight, createdAt, lastActivatedAt, provenance])
    }

    // MARK: - Private
}
