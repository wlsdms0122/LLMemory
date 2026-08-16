//
//  MarkNotesUsedTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct MarkNotesUsedTransaction: GRDBBrainTransaction {
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
    let sessionLabel: SessionId?
    let now: Int

    // MARK: - Initializer
    init(ids: [String], response: String?, sessionLabel: SessionId? = nil, now: Int) {
        self.ids = ids
        self.response = response
        self.sessionLabel = sessionLabel
        self.now = now
    }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> [UsedOutcome] {
        var outcomes: [UsedOutcome] = []
        let cutoff = now - Activation.usedLookbackSec(brain)

        for id in ids {
            let hit: Row?

            if let sessionLabel {
                hit = try Row.fetchOne(db, sql: """
                    SELECT h.id FROM retrieval_hits h
                    JOIN activity_windows w ON w.id = h.window_id
                    WHERE h.note_id = ? AND h.surfaced_at >= ? AND w.label = ?
                    ORDER BY h.surfaced_at DESC LIMIT 1
                    """, arguments: [id, cutoff, sessionLabel.rawValue])
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
