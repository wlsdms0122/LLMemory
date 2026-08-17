//
//  FetchDismissalsByNoteOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchDismissalsByNoteOperation: GRDBReadOperation {
    // MARK: - Property
    let kind: String

    // MARK: - Initializer
    init(kind: String) {
        self.kind = kind
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String: DismissalPolicy.Dismissal] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT note_id, dismiss_count, word_count, section_count, generation
            FROM candidate_dismissals WHERE kind = ?
            """, arguments: [kind])
        var dismissals: [String: DismissalPolicy.Dismissal] = [:]
        
        for row in rows {
            dismissals[row["note_id"]] = DismissalPolicy.Dismissal(
                kind: kind,
                dismissCount: row["dismiss_count"] as Int? ?? 1,
                wordCount: row["word_count"] as Int? ?? 0,
                sectionCount: row["section_count"] as Int? ?? 0,
                generation: row["generation"] as Int? ?? 0
            )
        }
        
        return dismissals
    }

    // MARK: - Private
}
