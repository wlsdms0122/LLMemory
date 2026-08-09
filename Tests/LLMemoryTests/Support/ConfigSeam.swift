//
//  ConfigSeam.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/10/26.
//

import Foundation
import GRDB
@testable import LLMemory

// Test-only config writer — production mutates config through transactions
// inside a scope; fixtures set a row and prime the fixture's cache directly.
extension Config {
    static func set(_ queue: any DatabaseWriter, _ key: String, value: Any) throws {
        let stringValue = "\(value)"

        try queue.write { db in
            try MetaRecord(key: prefix + key, value: stringValue).upsert(db)
        }

        cacheOverrideForTesting(key, value: stringValue)
    }
}
