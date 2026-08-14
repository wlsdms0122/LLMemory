//
//  FetchSplitShapeRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Candidate-domain transactions — row access for the restructuring detector.
// What counts as a candidate is Candidates' (Service tier) policy; these
// only fetch, returning neutral rows.
struct FetchSplitShapeRowsTransaction: GRDBReadTransaction {
    struct SplitShape {
        // MARK: - Property
        let id: String
        let title: String
        let wordCount: Int
        let sectionCount: Int
        let tagCount: Int

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    let minWords: Int
    let minSections: Int

    private let policy = Policy()

    // MARK: - Initializer
    init(minWords: Int, minSections: Int) {
        self.minWords = minWords
        self.minSections = minSections
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [SplitShape] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, n.word_count, n.section_count,
                   (SELECT COUNT(DISTINCT tag) FROM tags WHERE note_id = n.id) AS tag_count
            FROM notes n
            WHERE \(policy.decayCandidate())
              AND n.word_count >= ?
              AND n.section_count >= ?
            ORDER BY n.word_count DESC, n.id ASC
            """, arguments: [minWords, minSections]).map { row in
            SplitShape(
                id: row["id"],
                title: row["title"],
                wordCount: row["word_count"] as Int? ?? 0,
                sectionCount: row["section_count"] as Int? ?? 0,
                tagCount: row["tag_count"] as Int? ?? 0
            )
        }
    }

    // MARK: - Private
}
