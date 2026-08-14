//
//  FetchCandidateGenerationTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchCandidateGenerationTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> Int {
        (try Int.fetchOne(
            db,
            sql: "SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'candidate_generation'"
        )) ?? 0
    }

    // MARK: - Private
}
