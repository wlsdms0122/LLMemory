//
//  FetchConfigRowsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Every committed config row, keyed as stored. What warms the parameter cache
// at boot and at the end of every write scope.
//
// A row whose value is NULL is a value the brain has deliberately unset; it
// comes back as the sentinel so the cache can tell it apart from a key that
// was never written.
struct FetchConfigRowsTransaction: GRDBReadTransaction {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    func perform(_ db: Database) throws -> [String: String] {
        var rows: [String: String] = [:]

        for record in try MetaRecord.filter(Column("key").like("\(Config.prefix)%")).fetchAll(db) {
            rows[record.key] = record.value ?? Config.nilSentinel
        }

        return rows
    }

    // MARK: - Private
}
