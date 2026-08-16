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
            config: brain.config
        )
    }

    // MARK: - Private
}
