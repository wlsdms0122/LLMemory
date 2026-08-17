//
//  TagInUseOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct TagInUseOperation: GRDBReadOperation {
    // MARK: - Property
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: "SELECT 1 FROM tags WHERE tag = ? LIMIT 1",
            arguments: [tag]
        ) != nil
    }

    // MARK: - Private
}
