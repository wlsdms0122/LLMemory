//
//  DropTagAliasClaimOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// A spelling that becomes a canonical tag cannot stay an alias — reprojection
// canonicalises frontmatter tags through tag_aliases, so a stale claim would
// silently rewrite the new tag back to its old canonical.
struct DropTagAliasClaimOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = String
    let alias: String

    // MARK: - Initializer
    init(alias: String) {
        self.alias = alias
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM tag_aliases WHERE alias = ?", arguments: [alias])
    }

    // MARK: - Private
}
