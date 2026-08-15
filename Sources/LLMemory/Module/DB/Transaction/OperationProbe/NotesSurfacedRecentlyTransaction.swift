//
//  NotesSurfacedRecentlyTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Read-only union check for mark_used validation — a note counts as
// surfaced when it appears in a derived hit *or* in a retrieval event not
// yet succeeded into hits, so validation never needs to write. Set-valued:
// the batch is judged with one hits query and one event scan.
struct NotesSurfacedRecentlyTransaction: GRDBReadTransaction {
    // MARK: - Property
    // Keeps each IN (...) under SQLite's bind-variable ceiling — batch size
    // must not decide the judgement's error path.
    private static let chunkSize = 500

    let noteIds: [String]
    let cutoff: Int
    let label: SessionId?

    // MARK: - Initializer
    init(noteIds: [String], cutoff: Int, label: SessionId? = nil) {
        self.noteIds = noteIds
        self.cutoff = cutoff
        self.label = label
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> Set<String> {
        guard !noteIds.isEmpty else { return [] }

        var surfaced = Set<String>()
        let wanted = Set(noteIds)
        let chunks = stride(from: 0, to: noteIds.count, by: Self.chunkSize).map { start in
            Array(noteIds[start..<min(start + Self.chunkSize, noteIds.count)])
        }

        for chunk in chunks {
            let placeholders = chunk.map { _ in "?" }.joined(separator: ",")

            if let label {
                surfaced.formUnion(try String.fetchAll(db, sql: """
                    SELECT DISTINCT h.note_id FROM retrieval_hits h
                    JOIN activity_windows w ON w.id = h.window_id
                    WHERE h.note_id IN (\(placeholders)) AND h.surfaced_at >= ? AND w.label = ?
                    """, arguments: StatementArguments(
                        chunk + [cutoff, label.rawValue] as [DatabaseValueConvertible])))
            } else {
                surfaced.formUnion(try String.fetchAll(db, sql: """
                    SELECT DISTINCT note_id FROM retrieval_hits
                    WHERE note_id IN (\(placeholders)) AND surfaced_at >= ?
                    """, arguments: StatementArguments(chunk + [cutoff] as [DatabaseValueConvertible])))
            }
        }

        if surfaced.isSuperset(of: wanted) { return surfaced }

        let rows: [Row]

        if let label {
            rows = try Row.fetchAll(db, sql: """
                SELECT payload FROM events
                WHERE kind = 'retrieval' AND ts >= ? AND session_id = ?
                """, arguments: [cutoff, label.rawValue])
        } else {
            rows = try Row.fetchAll(db, sql: """
                SELECT payload FROM events WHERE kind = 'retrieval' AND ts >= ?
                """, arguments: [cutoff])
        }

        for row in rows {
            guard let raw = row["payload"] as String?,
                let data = raw.data(using: .utf8),
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }

            let ids = (payload["hit_ids"] as? [String] ?? [])
                + (payload["expand_ids"] as? [String] ?? [])

            surfaced.formUnion(wanted.intersection(ids))

            if surfaced.isSuperset(of: wanted) { break }
        }

        return surfaced
    }

    // MARK: - Private
}
