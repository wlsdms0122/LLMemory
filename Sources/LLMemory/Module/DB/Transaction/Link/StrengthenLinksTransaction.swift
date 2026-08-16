//
//  StrengthenLinksTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct StrengthenLinksTransaction: GRDBTransaction {
    // MARK: - Property
    let pairs: [(String, String)]
    let kind: LinkKind
    let step: Double?
    let cap: Double?

    // MARK: - Initializer
    init(
        pairs: [(String, String)],
        kind: LinkKind = .cooccur,
        step: Double? = nil,
        cap: Double? = nil
    ) {
        self.pairs = pairs
        self.kind = kind
        self.step = step
        self.cap = cap
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> Int {
        guard !pairs.isEmpty else { return 0 }

        let stepValue = step ?? Genes.double("links.strengthen_step")
        let now = Int(Date().timeIntervalSince1970)
        var strengthened = 0

        for (src, dst) in pairs {
            guard let (source, destination) = kind.endpoints(src: src, dst: dst) else {
                continue
            }

            if let cap {
                try db.execute(sql: """
                    INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(src, dst, kind) DO UPDATE SET
                      weight = MIN(?, weight + excluded.weight),
                      last_activated_at = excluded.last_activated_at
                    """, arguments: [
                        source, destination, kind.rawValue, min(stepValue, cap), now, now, cap
                    ])
            } else {
                try db.execute(sql: """
                    INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(src, dst, kind) DO UPDATE SET
                      weight = weight + excluded.weight,
                      last_activated_at = excluded.last_activated_at
                    """, arguments: [source, destination, kind.rawValue, stepValue, now, now])
            }

            strengthened += 1
        }

        return strengthened
    }

    // MARK: - Private
}
