//
//  LinkSiblingsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct LinkSiblingsOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = ([String], Int)
    let ids: [String]
    let now: Int

    // MARK: - Initializer
    init(ids: [String], now: Int) {
        self.ids = ids
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        let sorted = ids.sorted()

        guard sorted.count >= 2 else { return }

        for (index, left) in sorted.enumerated() {
            for right in sorted.dropFirst(index + 1) {
                guard let (src, dst) = LinkKind.sibling.endpoints(src: left, dst: right) else {
                    continue
                }

                try db.execute(sql: """
                    INSERT OR IGNORE INTO note_links
                      (src, dst, kind, weight, created_at, last_activated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [src, dst, LinkKind.sibling.rawValue, 1.0, now, now])
            }
        }
    }

    // MARK: - Private
}
