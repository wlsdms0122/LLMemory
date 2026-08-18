//
//  FetchNotesWithTagOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNotesWithTagOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = String
    let tag: String

    // MARK: - Initializer
    init(tag: String) {
        self.tag = tag
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT DISTINCT note_id FROM tags WHERE tag = ?",
            arguments: [tag]
        )
    }

    // MARK: - Private
}
