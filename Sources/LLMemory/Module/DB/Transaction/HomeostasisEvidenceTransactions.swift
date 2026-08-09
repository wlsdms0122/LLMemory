//
//  HomeostasisEvidenceTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Evidence probes for the homeostatic tick — closed activity windows past
// the watermark and the expand-landing outcomes inside one window.
struct FetchClosedActivityWindowsTransaction: GRDBReadTransaction {
    struct Window {
        // MARK: - Property
        let id: Int
        let sighted: Bool

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let watermark: Int
    let closedBefore: Int

    // MARK: - Initializer
    init(watermark: Int, closedBefore: Int) {
        self.watermark = watermark
        self.closedBefore = closedBefore
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Window] {
        let firstGet = try Int.fetchOne(
            db,
            sql: "SELECT MIN(surfaced_at) FROM retrieval_hits WHERE cmd = 'get'"
        )
        let sightedSince = firstGet ?? Int.max
        let candidates = try Row.fetchAll(db, sql: """
            SELECT id, ended_at, started_at FROM activity_windows WHERE id > ?
            ORDER BY id
            """, arguments: [watermark])
        var windows: [Window] = []

        for candidate in candidates {
            let endedAt: Int = candidate["ended_at"]

            if endedAt >= closedBefore { break }

            let startedAt: Int = candidate["started_at"]
            windows.append(Window(id: candidate["id"], sighted: startedAt >= sightedSince))
        }

        return windows
    }

    // MARK: - Private
}

struct FetchExpandEvidenceTransaction: GRDBReadTransaction {
    // MARK: - Property
    let windowId: Int

    // MARK: - Initializer
    init(windowId: Int) {
        self.windowId = windowId
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (seen: Int, landed: Int) {
        let rows = try Row.fetchAll(db, sql: """
            SELECT h.note_id, h.surfaced_at,
                   EXISTS (
                     SELECT 1 FROM retrieval_hits g
                     WHERE g.window_id = h.window_id AND g.note_id = h.note_id
                       AND g.cmd = 'get' AND g.surfaced_at >= h.surfaced_at
                   ) AS landed
            FROM retrieval_hits h
            WHERE h.window_id = ? AND h.surface_kind = 'expand' AND h.cmd != 'get'
            """, arguments: [windowId])

        return (rows.count, rows.filter { row in (row["landed"] as Int? ?? 0) == 1 }.count)
    }

    // MARK: - Private
}
