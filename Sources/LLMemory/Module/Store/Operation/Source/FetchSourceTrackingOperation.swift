//
//  FetchSourceTrackingOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Every note whose sources were ever fingerprinted. A row with no
// fingerprint is not tracked and never comes back.
struct FetchSourceTrackingOperation: GRDBReadOperation {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func execute(_ db: Database) throws -> [SourceTracking] {
        try Row.fetchAll(db, sql: """
            SELECT note_id, source_hash, source_stale, decl_hash FROM note_source
            WHERE source_hash IS NOT NULL
            """)
            .map(SourceTracking.init)
    }

    // MARK: - Private
}
