//
//  FetchNoteIdsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteIdsTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT id FROM notes"))
    }

    // MARK: - Private
}
