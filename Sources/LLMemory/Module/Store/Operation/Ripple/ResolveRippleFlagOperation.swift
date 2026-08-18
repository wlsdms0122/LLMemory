//
//  ResolveRippleFlagOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ResolveRippleFlagOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, String, String?, Int)
    let noteId: String
    let kind: String
    let reason: String?
    let now: Int

    // MARK: - Initializer
    init(noteId: String, kind: String, reason: String?, now: Int) {
        self.noteId = noteId
        self.kind = kind
        self.reason = reason
        self.now = now
    }

    // MARK: - Public
    @discardableResult
    func execute(_ db: Database) throws -> Int {
        try db.execute(sql: """
            UPDATE ripple_flags SET resolved_at = ?
            WHERE note_id = ? AND flag = ? AND resolved_at IS NULL
            """, arguments: [now, noteId, kind])

        let resolved = db.changesCount

        if resolved > 0 {
            let trimmed = reason?.unicodeScalarPrefix(200)

            try db.execute(sql: """
                INSERT INTO note_lifecycle_events (note_id, kind, reason, created_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [noteId, "flag_resolved", "\(kind): \(trimmed ?? "")", now])
        }

        return resolved
    }

    // MARK: - Private
}
