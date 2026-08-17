//
//  FetchClosedActivityWindowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Evidence probes for the homeostatic tick — closed activity windows past
// the watermark and the expand-landing outcomes inside one window.
struct FetchClosedActivityWindowsOperation: GRDBReadOperation {
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
    func execute(_ db: Database) throws -> [Window] {
        let firstGet = try Int.fetchOne(
            db,
            sql: "SELECT MIN(surfaced_at) FROM retrieval_hits WHERE cmd = ?",
            arguments: [RetrievalCommand.get.rawValue]
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
