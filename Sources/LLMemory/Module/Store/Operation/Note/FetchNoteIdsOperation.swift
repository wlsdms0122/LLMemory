//
//  FetchNoteIdsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchNoteIdsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Never

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT id FROM notes"))
    }

    // MARK: - Private
}
