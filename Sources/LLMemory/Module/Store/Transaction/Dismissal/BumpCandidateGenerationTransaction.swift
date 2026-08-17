//
//  BumpCandidateGenerationTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct BumpCandidateGenerationTransaction: GRDBTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws {
        let generation = try FetchCandidateGenerationTransaction().perform(db)
        
        try db.execute(sql: """
            INSERT INTO meta (key, value) VALUES ('candidate_generation', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """, arguments: [String(generation + 1)])
    }

    // MARK: - Private
}
