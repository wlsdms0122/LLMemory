//
//  FetchExpandEvidenceOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchExpandEvidenceOperation: GRDBReadOperation {
    // MARK: - Property
    let windowId: Int

    // MARK: - Initializer
    init(windowId: Int) {
        self.windowId = windowId
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> (seen: Int, landed: Int) {
        let rows = try Row.fetchAll(db, sql: """
            SELECT h.note_id, h.surfaced_at,
                   EXISTS (
                     SELECT 1 FROM retrieval_hits g
                     WHERE g.window_id = h.window_id AND g.note_id = h.note_id
                       AND g.cmd = ? AND g.surfaced_at >= h.surfaced_at
                   ) AS landed
            FROM retrieval_hits h
            WHERE h.window_id = ? AND h.surface_kind = ? AND h.cmd != ?
            """, arguments: [
                RetrievalCommand.get.rawValue,
                windowId,
                SurfaceKind.expand.rawValue,
                RetrievalCommand.get.rawValue
            ])

        return (rows.count, rows.filter { row in (row["landed"] as Int? ?? 0) == 1 }.count)
    }

    // MARK: - Private
}
