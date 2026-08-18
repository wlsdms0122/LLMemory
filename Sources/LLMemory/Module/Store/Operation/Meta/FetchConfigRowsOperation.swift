//
//  FetchConfigRowsOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Every committed config row, keyed the way a caller spells a config key.
// All three config operations take that spelling and add the stored prefix
// themselves, so the prefix never travels in a signature.
//
// A NULL value comes back as a present nil: the brain unset that key on
// purpose, which is not the same as never having written it. How a cache
// keeps those two apart is the cache's problem, not this row's.
struct FetchConfigRowsOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = Never
    // MARK: - Initializer
    // MARK: - Public
    func execute(_ db: Database) throws -> [String: String?] {
        var rows: [String: String?] = [:]

        for record in try MetaRecord.filter(Column("key").like("\(Config.prefix)%")).fetchAll(db) {
            rows[String(record.key.dropFirst(Config.prefix.count))] = record.value
        }

        return rows
    }

    // MARK: - Private
}
