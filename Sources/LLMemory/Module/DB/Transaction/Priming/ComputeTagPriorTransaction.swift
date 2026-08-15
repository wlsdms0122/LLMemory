//
//  ComputeTagPriorTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Derives the recent-retrieval tag prior for a session — the frequency
// distribution of tags among recently surfaced notes. Contextual reinstatement
// runs over every tag a note carries, not one privileged category: a note lives
// in as many contexts as it has tags, and the session decides which one is warm.
struct ComputeTagPriorTransaction: GRDBReadTransaction {
    // MARK: - Property
    let sessionId: SessionId
    let windowSec: Int
    let now: Int

    // MARK: - Initializer
    init(sessionId: SessionId, windowSec: Int, now: Int) {
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
            arguments: [sessionId.rawValue, cutoff]
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
        let tagRows = try Row.fetchAll(
            db,
            sql: "SELECT note_id, tag FROM tags WHERE note_id IN (\(placeholders))",
            arguments: StatementArguments(unique)
        )
        var tagsById: [String: [String]] = [:]

        for row in tagRows {
            tagsById[row["note_id"] as String, default: []].append(row["tag"] as String)
        }

        var frequency: [String: Double] = [:]
        var counted = 0

        for id in ids {
            guard let tags = tagsById[id] else { continue }

            counted += 1

            for tag in tags { frequency[tag, default: 0] += 1 }
        }

        // Normalised by the number of hits, not by how many tags they carried
        // between them: a tag on every hit is a prior of 1, whether those notes
        // wear one tag each or five. Dividing by tag occurrences would make the
        // boost quietly weaker on a corpus that tags more richly, and
        // priming.alpha means "how much say priming has" on a fixed scale.
        guard counted > 0 else { return [:] }

        return frequency.mapValues { count in count / Double(counted) }
    }

    // MARK: - Private
}
