//
//  RecordDismissalOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RecordDismissalOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (LintTarget, String, String?, Int)
    let target: LintTarget
    let kind: String
    let reason: String?
    let now: Int

    // MARK: - Initializer
    init(target: LintTarget, kind: String, reason: String?, now: Int) {
        self.target = target
        self.kind = kind
        self.reason = reason
        self.now = now
    }

    init(noteId: String, kind: String, reason: String?, now: Int) {
        self.init(target: .note(noteId), kind: kind, reason: reason, now: now)
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        switch target {
        case .note(let noteId):
            try recordNote(db, noteId: noteId)
        
        case .corpus(let key):
            try db.execute(sql: """
                INSERT INTO corpus_dismissals
                    (target_key, kind, dismiss_count, generation, reason, last_dismissed_at)
                VALUES (?, ?, 1, ?, ?, ?)
                ON CONFLICT(target_key, kind) DO UPDATE SET
                    dismiss_count = dismiss_count + 1,
                    generation = excluded.generation,
                    reason = excluded.reason,
                    last_dismissed_at = excluded.last_dismissed_at
                """, arguments: [key, kind, try FetchCandidateGenerationOperation().execute(db), reason, now])
        }
    }

    // MARK: - Private
    private func recordNote(_ db: Database, noteId: String) throws {
        let shape = try Row.fetchOne(
            db,
            sql: "SELECT word_count, section_count FROM notes WHERE id = ?",
            arguments: [noteId]
        )
        let wordCount = (shape?["word_count"] as Int?) ?? 0
        let sectionCount = (shape?["section_count"] as Int?) ?? 0
        let generation = try FetchCandidateGenerationOperation().execute(db)
        
        try db.execute(sql: """
            INSERT INTO candidate_dismissals
                (note_id, kind, dismiss_count, word_count, section_count, generation, reason, last_dismissed_at)
            VALUES (?, ?, 1, ?, ?, ?, ?, ?)
            ON CONFLICT(note_id, kind) DO UPDATE SET
                dismiss_count = dismiss_count + 1,
                word_count = excluded.word_count,
                section_count = excluded.section_count,
                generation = excluded.generation,
                reason = excluded.reason,
                last_dismissed_at = excluded.last_dismissed_at
            """, arguments: [noteId, kind, wordCount, sectionCount, generation, reason, now])
    }
}
