//
//  FetchIndexedNoteIdsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Which notes the search index currently holds rows for. Compared against the
// catalog, the difference in either direction is a defect.
struct FetchIndexedNoteIdsOperation: GRDBReadOperation {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT DISTINCT id FROM notes_fts")
    }

    // MARK: - Private
}
