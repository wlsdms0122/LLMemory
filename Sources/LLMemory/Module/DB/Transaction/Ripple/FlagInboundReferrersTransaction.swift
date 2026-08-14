//
//  FlagInboundReferrersTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// ripple_flags transactions — flag propagation to referrers, flag upsert
// with lifecycle provenance, and resolution.
struct FlagInboundReferrersTransaction: GRDBTransaction {
    // MARK: - Property
    let targetId: String
    let reason: String
    let now: Int

    // MARK: - Initializer
    init(targetId: String, reason: String, now: Int) {
        self.targetId = targetId
        self.reason = reason
        self.now = now
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> Int {
        let referrers = try String.fetchAll(db, sql: """
            SELECT DISTINCT src FROM note_links WHERE dst = ? AND src != ? AND kind = ?
            """, arguments: [targetId, targetId, Links.kindReference])

        for referrer in referrers {
            try AddRippleFlagTransaction(noteId: referrer, kind: "stale_ref", reason: reason, now: now)
                .perform(db)
        }

        return referrers.count
    }

    // MARK: - Private
}
