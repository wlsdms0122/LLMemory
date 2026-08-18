//
//  FetchConfigValueOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// One committed config row. Config answers from the warmed cache, which is
// the right answer everywhere except inside the write that is setting the
// value — there the row is ahead of the cache, so the row is what is asked.
struct FetchConfigValueOperation: GRDBReadOperation {
    // MARK: - Property
    typealias Parameter = (String, String)
    let key: String
    let defaultValue: String

    // MARK: - Initializer
    init(key: String, default defaultValue: String) {
        self.key = key
        self.defaultValue = defaultValue
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> String {
        let stored = try MetaRecord.fetchOne(db, key: Config.prefix + key)?.value

        return (stored ?? nil) ?? defaultValue
    }

    // MARK: - Private
}
