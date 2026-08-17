//
//  CanonicalizeTagOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct CanonicalizeTagOperation: GRDBReadOperation {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> String {
        let canonical = try String.fetchOne(
            db,
            sql: "SELECT canonical FROM tag_aliases WHERE alias = ?",
            arguments: [tag]
        )

        return canonical ?? tag
    }

    // MARK: - Private
}
