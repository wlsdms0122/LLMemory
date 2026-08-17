//
//  ConfigSeam.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/10/26.
//

import Foundation
import GRDB
@testable import LLMemory

// Test-only config writer — production mutates config through an operation
// inside a scope. A fixture commits the row and then re-reads the caches the
// way a write scope does, so what the test set up and what the process holds
// come from the same place.
extension Config {
    static func set(_ session: Session, _ key: String, value: Any) throws {
        try session.storage.connect().write { db in
            try MetaRecord(key: prefix + key, value: "\(value)").upsert(db)
        }

        session.rewarm()
    }
}
