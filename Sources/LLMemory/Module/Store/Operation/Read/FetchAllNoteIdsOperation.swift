//
//  FetchAllNoteIdsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Every catalogued id, in address order. What each id addresses is not asked
// here — the caller owns that grammar.
struct FetchAllNoteIdsOperation: GRDBReadOperation {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT id FROM notes ORDER BY id")
    }

    // MARK: - Private
}
