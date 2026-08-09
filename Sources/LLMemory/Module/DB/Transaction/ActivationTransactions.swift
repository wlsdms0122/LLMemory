//
//  ActivationTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Activation transactions — succession of raw retrieval events into the
// persistent traces (activity_windows / retrieval_hits) and their
// observation.
public struct ActivationStats: Encodable, Sendable {
    public struct AxisRow: Encodable, Sendable {
        // MARK: - Property
        public let axis: String
        public let surfaced: Int
        public let used: Int

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    public let windows: Int
    public let labeledWindows: Int
    public let surfaced: Int
    public let used: Int
    public let byAxis: [AxisRow]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

enum Activation {
    enum UsedError: Error, CustomStringConvertible {
        case notSurfaced(String)

        var description: String {
            switch self {
            case .notSurfaced(let id):
                return "note '\(id)' was not surfaced in any recent activity window — cannot mark unobserved usage"
            }
        }
    }

    // MARK: - Property
    static let watermarkKey = "activation.derive_watermark"

    static var windowGapSec: Int { Genes.int("activation.window_gap_sec") }

    static var usedLookbackSec: Int {
        Config.getInt("activation.used_lookback_sec", default: 86_400)
    }

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

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
            let sessionId: String? = row["session_id"]
            lastId = eventId

            guard let payload = parsePayload(row["payload"]) else { continue }

            result.eventsConsumed += 1

            let windowId = try openWindow(db, ts: timestamp, label: sessionId)
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

struct MarkNotesUsedTransaction: GRDBTransaction {
    struct UsedOutcome {
        // MARK: - Property
        let noteId: String
        let signal: String
        let matched: Bool

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let ids: [String]
    let response: String?
    let sessionLabel: String?
    let now: Int

    // MARK: - Initializer
    init(ids: [String], response: String?, sessionLabel: String? = nil, now: Int) {
        self.ids = ids
        self.response = response
        self.sessionLabel = sessionLabel
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [UsedOutcome] {
        var outcomes: [UsedOutcome] = []
        let cutoff = now - Activation.usedLookbackSec

        for id in ids {
            let hit: Row?

            if let sessionLabel, !sessionLabel.isEmpty {
                hit = try Row.fetchOne(db, sql: """
                    SELECT h.id FROM retrieval_hits h
                    JOIN activity_windows w ON w.id = h.window_id
                    WHERE h.note_id = ? AND h.surfaced_at >= ? AND w.label = ?
                    ORDER BY h.surfaced_at DESC LIMIT 1
                    """, arguments: [id, cutoff, sessionLabel])
            } else {
                hit = try Row.fetchOne(db, sql: """
                    SELECT id FROM retrieval_hits WHERE note_id = ? AND surfaced_at >= ?
                    ORDER BY surfaced_at DESC LIMIT 1
                    """, arguments: [id, cutoff])
            }

            guard let hit else { throw Activation.UsedError.notSurfaced(id) }

            var signal = "reported"
            var matched = true

            if let response {
                matched = try overlaps(db, noteId: id, response: response)
                signal = "content_overlap"
            }

            if matched {
                let hitId: Int64 = hit["id"]

                try db.execute(sql: """
                    UPDATE retrieval_hits SET used_signal = ?, used_at = ? WHERE id = ?
                    """, arguments: [signal, now, hitId])
            }

            outcomes.append(UsedOutcome(noteId: id, signal: signal, matched: matched))
        }

        return outcomes
    }

    // MARK: - Private
    private func overlaps(
        _ db: Database,
        noteId: String,
        response: String
    ) throws -> Bool {
        let row = try Row.fetchOne(db, sql: """
            SELECT n.title, n.summary FROM notes n WHERE n.id = ?
            """, arguments: [noteId])
        let title: String = row?["title"] ?? ""
        let summary: String = row?["summary"] ?? ""
        let responseTokens = tokens(response)

        guard !responseTokens.isEmpty else { return false }

        if response.contains(noteId) { return true }

        let noteTokens = tokens(title + " " + summary)

        guard !noteTokens.isEmpty else { return false }

        let shared = noteTokens.intersection(responseTokens)

        return Double(shared.count) / Double(noteTokens.count) >= 0.3
    }

    private func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { token in token.count >= 2 }
        )
    }
}

struct FetchActivationStatsTransaction: GRDBTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> ActivationStats {
        let windows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_windows") ?? 0
        let labeled = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM activity_windows WHERE label IS NOT NULL"
        ) ?? 0
        let surfaced = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM retrieval_hits") ?? 0
        let used = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM retrieval_hits WHERE used_signal IS NOT NULL"
        ) ?? 0
        let axisRows = try Row.fetchAll(db, sql: """
            SELECT COALESCE(n.axis, '(gone)') AS axis,
                   COUNT(*) AS surfaced,
                   SUM(CASE WHEN h.used_signal IS NOT NULL THEN 1 ELSE 0 END) AS used
            FROM retrieval_hits h LEFT JOIN notes n ON n.id = h.note_id
            GROUP BY COALESCE(n.axis, '(gone)') ORDER BY surfaced DESC
            """)
        let byAxis = axisRows.map { row in
            ActivationStats.AxisRow(
                axis: row["axis"],
                surfaced: row["surfaced"],
                used: row["used"] ?? 0
            )
        }

        return ActivationStats(
            windows: windows,
            labeledWindows: labeled,
            surfaced: surfaced,
            used: used,
            byAxis: byAxis
        )
    }

    // MARK: - Private
}
