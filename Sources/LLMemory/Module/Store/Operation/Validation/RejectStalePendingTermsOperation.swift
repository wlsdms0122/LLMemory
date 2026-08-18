//
//  RejectStalePendingTermsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RejectStalePendingTermsOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = Int
    let maxAgeSec: Int

    // MARK: - Initializer
    init(maxAgeSec: Int = 86400) {
        self.maxAgeSec = maxAgeSec
    }

    // MARK: - Public
    @discardableResult
    func execute(_ db: Database) throws -> Int {
        let now = Int(Date().timeIntervalSince1970)

        try db.execute(sql: """
            UPDATE note_retrieval_terms
            SET status = 'rejected', reject_reason = ?, validated_at = ?
            WHERE status = 'pending' AND created_at <= ?
            """, arguments: ["roundtrip_fail", now, now - maxAgeSec])

        return db.changesCount
    }

    // MARK: - Private
}
