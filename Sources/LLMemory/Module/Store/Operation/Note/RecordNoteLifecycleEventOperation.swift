//
//  RecordNoteLifecycleEventOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RecordNoteLifecycleEventOperation: GRDBOperation {
    // MARK: - Property
    let nid: String
    let kind: String
    let reason: String?
    let now: Int

    // MARK: - Initializer
    init(nid: String, kind: String, reason: String?, now: Int) {
        self.nid = nid
        self.kind = kind
        self.reason = reason
        self.now = now
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        let trimmedReason = reason.map { text in String(text.prefix(200)) }

        try db.execute(sql: """
            INSERT INTO note_lifecycle_events (note_id, kind, reason, created_at)
            VALUES (?, ?, ?, ?)
            """, arguments: [nid, kind, trimmedReason, now])
    }

    // MARK: - Private
}
