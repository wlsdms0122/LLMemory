//
//  FetchFlaggedRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchFlaggedRowsTransaction: GRDBReadTransaction {
    struct FlaggedNote {
        // MARK: - Property
        let noteId: String
        let reason: String?
        let createdAt: Int
        let title: String
        let summary: String?

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let flag: String
    let limit: Int

    private let policy = Policy()

    // MARK: - Initializer
    init(flag: String, limit: Int) {
        self.flag = flag
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [FlaggedNote] {
        try Row.fetchAll(db, sql: """
            SELECT r.note_id, r.reason, r.created_at, n.title, n.summary
            FROM ripple_flags r
            JOIN notes n ON n.id = r.note_id
            WHERE r.flag = ? AND r.resolved_at IS NULL
              AND \(policy.surface())
            ORDER BY r.created_at ASC, r.note_id ASC
            LIMIT ?
            """, arguments: [flag, limit]).map { row in
            FlaggedNote(
                noteId: row["note_id"],
                reason: row["reason"] as String?,
                createdAt: row["created_at"],
                title: row["title"],
                summary: row["summary"] as String?
            )
        }
    }

    // MARK: - Private
}
