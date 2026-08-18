//
//  DeriveActivityWindowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct DeriveActivityWindowsOperation: GRDBOperation {
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
    typealias Parameter = (Int, Int)
    let now: Int
    let windowGapSec: Int

    // MARK: - Initializer
    init(now: Int, windowGapSec: Int) {
        self.now = now
        self.windowGapSec = windowGapSec
    }

    // MARK: - Public
    @discardableResult
    func execute(_ db: Database) throws -> DeriveResult {
        var result = DeriveResult()
        let watermark = Int(
            try FetchConfigValueOperation(key: Activation.watermarkKey, default: "0").execute(db)
        ) ?? 0
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, ts, session_id, payload FROM events
            WHERE kind = ? AND id > ? ORDER BY id
            """, arguments: [EventKind.retrieval.rawValue, watermark])

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

            // Copied through rather than re-spelled: for a payload this
            // binary wrote, cmd is already a RetrievalCommand — the fallback
            // marks a payload it could not attribute to one.
            let cmd = payload.cmd ?? "unknown"

            for id in payload.hitIds {
                try insertHit(
                    db,
                    windowId: windowId,
                    noteId: id,
                    ts: timestamp,
                    cmd: cmd,
                    kind: .hit
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
                    kind: .expand
                )
                result.hitsRecorded += 1
            }
        }

        try SetConfigValueOperation(key: Activation.watermarkKey, value: "\(lastId)").execute(db)

        result.windowsTouched = touched.count

        return result
    }

    // MARK: - Private
    private func openWindow(
        _ db: Database,
        ts: Int,
        label: String?
    ) throws -> Int64 {
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

            if ts - endedAt <= windowGapSec {
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
        kind: SurfaceKind
    ) throws {
        try db.execute(sql: """
            INSERT INTO retrieval_hits (window_id, note_id, surfaced_at, cmd, surface_kind)
            VALUES (?, ?, ?, ?, ?)
            """, arguments: [windowId, noteId, ts, cmd, kind.rawValue])
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
