//
//  CountEagerNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct CountEagerNotesTransaction: GRDBReadTransaction {
    private let policy = Policy()

    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM notes WHERE \(policy.eager(""))") ?? 0
    }

    // MARK: - Private
}
