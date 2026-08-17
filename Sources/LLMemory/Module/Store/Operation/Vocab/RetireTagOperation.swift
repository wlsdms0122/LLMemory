//
//  RetireTagOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RetireTagOperation: GRDBOperation {
    // MARK: - Property
    let tag: String
    let successor: String

    // MARK: - Initializer
    init(tag: String, successor: String) {
        self.tag = tag
        self.successor = successor
    }

    // MARK: - Public
    func execute(_ db: Database) throws {
        try db.execute(
            sql: "DELETE FROM tag_aliases WHERE canonical = ? AND alias = ?",
            arguments: [tag, successor]
        )
        try db.execute(
            sql: "UPDATE tag_aliases SET canonical = ? WHERE canonical = ?",
            arguments: [successor, tag]
        )
        try db.execute(sql: "DELETE FROM tag_vocab WHERE tag = ?", arguments: [tag])
    }

    // MARK: - Private
}
