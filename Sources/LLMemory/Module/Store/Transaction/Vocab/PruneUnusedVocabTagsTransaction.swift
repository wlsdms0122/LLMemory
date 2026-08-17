//
//  PruneUnusedVocabTagsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct PruneUnusedVocabTagsTransaction: GRDBTransaction {
    // MARK: - Property
    let protected: Set<String>

    // MARK: - Initializer
    init(protected: Set<String> = []) {
        self.protected = protected
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        var protectedTags = protected
        // Canonicals of tag_aliases are always protected for referential integrity.
        let canonicals = try String.fetchAll(db, sql: "SELECT DISTINCT canonical FROM tag_aliases")
        protectedTags.formUnion(canonicals)

        let rows = try String.fetchAll(db, sql: """
            SELECT tv.tag FROM tag_vocab tv
            LEFT JOIN tags t ON t.tag = tv.tag WHERE t.tag IS NULL
            """)
        let pruned = rows.filter { tag in !protectedTags.contains(tag) }

        for tag in pruned {
            try db.execute(sql: "DELETE FROM tag_vocab WHERE tag = ?", arguments: [tag])
        }

        return pruned
    }

    // MARK: - Private
}
