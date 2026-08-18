//
//  FetchLintCorpusIndexOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Lint-domain operations — row access for the note inspector. What counts
// as a defect is LintService's rule catalog; these only fetch.
struct FetchLintCorpusIndexOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = (Int, Int)
    let oversizedWords: Int
    let growthMinDatedSections: Int

    // MARK: - Initializer
    init(oversizedWords: Int, growthMinDatedSections: Int) {
        self.oversizedWords = oversizedWords
        self.growthMinDatedSections = growthMinDatedSections
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> LintCorpusIndex {
        var aliases: [String: String] = [:]

        for row in try Row.fetchAll(db, sql: "SELECT alias, canonical FROM tag_aliases") {
            aliases[row["alias"]] = row["canonical"]
        }

        return LintCorpusIndex(
            ids: Set(try String.fetchAll(db, sql: "SELECT id FROM notes")),
            tagAliases: aliases,
            oversizedWords: oversizedWords,
            growthMinDatedSections: growthMinDatedSections
        )
    }

    // MARK: - Private
}
