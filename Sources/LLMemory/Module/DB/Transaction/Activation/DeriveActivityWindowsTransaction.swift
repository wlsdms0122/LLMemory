//
//  DeriveActivityWindowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct DeriveActivityWindowsTransaction: GRDBTransaction {
    struct DeriveResult {
        // MARK: - Property
        var eventsConsumed = 0
        var windowsTouched = 0
        var hitsRecorded = 0

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    private struct RetrievalPayload {
        // MARK: - Property
        let cmd: String?
        let hitIds: [String]
        let expandIds: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let now: Int

    // MARK: - Initializer
    init(now: Int) {
        self.now = now
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> DeriveResult {
        var result = DeriveResult()
        let watermark = Int(Config.getStringTx(Activation.watermarkKey, default: "0", txDB: db)) ?? 0
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, ts, session_id, payload FROM events
            WHERE kind = 'retrieval' AND id > ? ORDER BY id
            """, arguments: [watermark])

        guard !rows.isEmpty else { return result }

        var touched = Set<Int64>()
        var lastId = watermark

        for row in rows {
            let eventId: Int = row["id"]
            let timestamp: Int = row["ts"]
            let sessionId = SessionId(row["session_id"])
            lastId = eventId

            guard let payload = parsePayload(row["payload"]) else { continue }

            result.eventsConsumed += 1

            let windowId = try openWindow(db, ts: timestamp, label: sessionId?.rawValue)
            touched.insert(windowId)

            try db.execute(sql: """
                UPDATE activity_windows SET ended_at = MAX(ended_at, ?), query_count = query_count + 1
                WHERE id = ?
                """, arguments: [timestamp, windowId])

            let cmd = payload.cmd ?? "unknown"

            for id in payload.hitIds {
                try insertHit(
                    db,
                    windowId: windowId,
                    noteId: id,
                    ts: timestamp,
                    cmd: cmd,
                    kind: "hit"
                )
                result.hitsRecorded += 1
            }

            for id in payload.expandIds {
                try insertHit(
                    db,
                    windowId: windowId,
                    noteId: id,
                    ts: timestamp,
                    cmd: cmd,
                    kind: "expand"
                )
                result.hitsRecorded += 1
            }
        }

        try Config.set(Activation.watermarkKey, value: lastId, txDB: db)

        result.windowsTouched = touched.count

        return result
    }

    // MARK: - Private
    private func openWindow(_ db: Database, ts: Int, label: String?) throws -> Int64 {
        let row: Row?

        if let label {
            row = try Row.fetchOne(db, sql: """
                SELECT id, ended_at FROM activity_windows WHERE label = ?
                ORDER BY ended_at DESC LIMIT 1
                """, arguments: [label])
        } else {
            row = try Row.fetchOne(db, sql: """
                SELECT id, ended_at FROM activity_windows WHERE label IS NULL
                ORDER BY ended_at DESC LIMIT 1
                """)
        }

        if let row {
            let endedAt: Int = row["ended_at"]

            if ts - endedAt <= Activation.windowGapSec {
                return row["id"]
            }
        }

        try db.execute(sql: """
            INSERT INTO activity_windows (started_at, ended_at, label, query_count)
            VALUES (?, ?, ?, 0)
            """, arguments: [ts, ts, label])

        return db.lastInsertedRowID
    }

    private func insertHit(
        _ db: Database,
        windowId: Int64,
        noteId: String,
        ts: Int,
        cmd: String,
        kind: String
    ) throws {
        try db.execute(sql: """
            INSERT INTO retrieval_hits (window_id, note_id, surfaced_at, cmd, surface_kind)
            VALUES (?, ?, ?, ?, ?)
            """, arguments: [windowId, noteId, ts, cmd, kind])
    }

    private func parsePayload(_ raw: String?) -> RetrievalPayload? {
        guard let raw,
            let data = raw.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        return RetrievalPayload(
            cmd: payload["cmd"] as? String,
            hitIds: payload["hit_ids"] as? [String] ?? [],
            expandIds: payload["expand_ids"] as? [String] ?? []
        )
    }
}
