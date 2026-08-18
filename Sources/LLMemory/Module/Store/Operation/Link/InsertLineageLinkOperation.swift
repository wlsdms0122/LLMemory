//
//  InsertLineageLinkOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct InsertLineageLinkOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, String, LinkKind, Int)
    let src: String
    let dst: String
    let kind: LinkKind
    let now: Int

    // MARK: - Initializer
    init(src: String, dst: String, kind: LinkKind, now: Int) {
        self.src = src
        self.dst = dst
        self.kind = kind
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        guard let (source, destination) = kind.endpoints(src: src, dst: dst) else { return }

        try db.execute(sql: """
            INSERT OR IGNORE INTO note_links
              (src, dst, kind, weight, created_at, last_activated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [source, destination, kind.rawValue, 1.0, now, now])
    }

    // MARK: - Private
}
