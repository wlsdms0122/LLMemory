//
//  FetchLintCorpusIndexTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Lint-domain transactions — row access for the note inspector. What counts
// as a defect is LintService's rule catalog; these only fetch.
struct FetchLintCorpusIndexTransaction: GRDBBrainReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database, _ brain: BrainContext) throws -> LintCorpusIndex {
        var aliases: [String: String] = [:]

        for row in try Row.fetchAll(db, sql: "SELECT alias, canonical FROM tag_aliases") {
            aliases[row["alias"]] = row["canonical"]
        }

        return LintCorpusIndex(
            ids: Set(try String.fetchAll(db, sql: "SELECT id FROM notes")),
            tagAliases: aliases,
            oversizedWords: brain.config.getInt("lint.oversized_words", default: 2_000),
            growthMinDatedSections: brain.config.getInt(
                "lint.growth_min_dated_sections",
                default: 8
            )
        )
    }

    // MARK: - Private
}
