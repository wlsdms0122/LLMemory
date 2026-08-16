//
//  FetchLintDismissalsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchLintDismissalsTransaction: GRDBReadTransaction {
    private let dismissalPolicy = DismissalPolicy()

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: DismissalPolicy.Dismissal] {
        var dismissals: [String: DismissalPolicy.Dismissal] = [:]
        let noteRows = try Row.fetchAll(db, sql: """
            SELECT note_id, kind, dismiss_count, word_count, section_count, generation
            FROM candidate_dismissals WHERE kind LIKE ?
            """, arguments: [DismissalPolicy.lintPrefix + "%"])
        
        for row in noteRows {
            let kind: String = row["kind"]
            
            guard dismissalPolicy.lintCode(of: kind) != nil else { continue }
            
            dismissals[dismissalPolicy.lintLookupKey(.note(row["note_id"]), kind)] = DismissalPolicy.Dismissal(
                kind: kind,
                dismissCount: row["dismiss_count"] as Int? ?? 1,
                wordCount: row["word_count"] as Int? ?? 0,
                sectionCount: row["section_count"] as Int? ?? 0,
                generation: row["generation"] as Int? ?? 0
            )
        }
        
        let corpusRows = try Row.fetchAll(db, sql: """
            SELECT target_key, kind, dismiss_count, generation
            FROM corpus_dismissals WHERE kind LIKE ?
            """, arguments: [DismissalPolicy.lintPrefix + "%"])
        
        for row in corpusRows {
            let kind: String = row["kind"]
            
            guard dismissalPolicy.lintCode(of: kind) != nil else { continue }
            
            dismissals[dismissalPolicy.lintLookupKey(.corpus(row["target_key"]), kind)] = DismissalPolicy.Dismissal(
                kind: kind,
                dismissCount: row["dismiss_count"] as Int? ?? 1,
                wordCount: 0,
                sectionCount: 0,
                generation: row["generation"] as Int? ?? 0
            )
        }
        
        return dismissals
    }

    // MARK: - Private
}
