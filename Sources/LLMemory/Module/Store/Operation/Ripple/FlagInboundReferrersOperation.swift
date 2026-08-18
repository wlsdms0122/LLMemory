//
//  FlagInboundReferrersOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// ripple_flags operations — flag propagation to referrers, flag upsert
// with lifecycle provenance, and resolution.
struct FlagInboundReferrersOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, String, Int)
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
    func execute(_ db: Database) throws -> Int {
        let referrers = try String.fetchAll(db, sql: """
            SELECT DISTINCT src FROM note_links WHERE dst = ? AND src != ? AND kind = ?
            """, arguments: [targetId, targetId, LinkKind.reference.rawValue])

        for referrer in referrers {
            try AddRippleFlagOperation(noteId: referrer, kind: "stale_ref", reason: reason, now: now)
                .execute(db)
        }

        return referrers.count
    }

    // MARK: - Private
}
