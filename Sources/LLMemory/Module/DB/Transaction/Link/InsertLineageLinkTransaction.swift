//
//  InsertLineageLinkTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct InsertLineageLinkTransaction: GRDBTransaction {
    // MARK: - Property
    let src: String
    let dst: String
    let kind: String
    let now: Int

    private let links = Links()

    // MARK: - Initializer
    init(src: String, dst: String, kind: String, now: Int) {
        self.src = src
        self.dst = dst
        self.kind = kind
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        guard let (source, destination) = links.normalize(src: src, dst: dst, kind: kind) else { return }

        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links
              (src, dst, kind, weight, created_at, last_activated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [source, destination, kind, 1.0, now, now])
    }

    // MARK: - Private
}
