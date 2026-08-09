//
//  PrimingTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Derives the recent-retrieval axis prior for a session — the frequency
// distribution of axes among recently surfaced notes.
struct ComputeAxisPriorTransaction: GRDBReadTransaction {
    // MARK: - Property
    let sessionId: String
    let windowSec: Int
    let now: Int

    // MARK: - Initializer
    init(sessionId: String, windowSec: Int, now: Int) {
        self.sessionId = sessionId
        self.windowSec = windowSec
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: Double] {
        let cutoff = now - windowSec
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT payload FROM events
                WHERE kind = 'retrieval' AND session_id = ? AND ts >= ?
                ORDER BY ts DESC, id DESC
                LIMIT 50
                """,
            arguments: [sessionId, cutoff]
        )

        if rows.isEmpty { return [:] }

        var ids: [String] = []

        for row in rows {
            let payloadJSON: String = row["payload"]

            guard let data = payloadJSON.data(using: .utf8),
                let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else {
                continue
            }

            if let hits = payload["hit_ids"] as? [String] { ids.append(contentsOf: hits) }
            if let expanded = payload["expand_ids"] as? [String] { ids.append(contentsOf: expanded) }
        }

        if ids.isEmpty { return [:] }

        let unique = Array(Set(ids))
        let placeholders = Array(repeating: "?", count: unique.count).joined(separator: ",")
        let axisRows = try Row.fetchAll(
            db,
            sql: "SELECT id, axis FROM notes WHERE id IN (\(placeholders))",
            arguments: StatementArguments(unique)
        )
        var axisById: [String: String] = [:]

        for row in axisRows {
            axisById[row["id"] as String] = row["axis"] as String
        }

        var frequency: [String: Double] = [:]

        for id in ids {
            guard let axis = axisById[id] else { continue }

            frequency[axis, default: 0] += 1
        }

        let total = frequency.values.reduce(0, +)

        guard total > 0 else { return [:] }

        return frequency.mapValues { count in count / total }
    }

    // MARK: - Private
}
