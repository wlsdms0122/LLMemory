//
//  FetchSplitShapeRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Row access for the restructuring detector. What counts as a candidate is
// CandidateDetector's to decide; this only fetches, returning neutral rows.
struct FetchSplitShapeRowsOperation: GRDBReadOperation {
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

    // MARK: - Initializer
    init(minWords: Int, minSections: Int) {
        self.minWords = minWords
        self.minSections = minSections
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [SplitShape] {
        try Row.fetchAll(db, sql: """
            SELECT n.id, n.title, n.word_count, n.section_count,
                   (SELECT COUNT(DISTINCT tag) FROM tags WHERE note_id = n.id) AS tag_count
            FROM notes n
            WHERE \(Policy.decayCandidate())
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
