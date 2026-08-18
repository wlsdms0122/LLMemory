//
//  FetchStaleSourceNoteIdsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchStaleSourceNoteIdsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Never

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT note_id FROM note_source WHERE source_stale = 1"))
    }

    // MARK: - Private
}
