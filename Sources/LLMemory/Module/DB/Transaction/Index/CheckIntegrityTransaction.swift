//
//  CheckIntegrityTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct CheckIntegrityTransaction: GRDBReadTransaction {
    // MARK: - Property
    let level: Indexer.IntegrityLevel

    private let indexer = Indexer()

    // MARK: - Initializer
    init(level: Indexer.IntegrityLevel = .l1) {
        self.level = level
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> (ok: Bool, msgs: [String]) {
        try indexer.check(db, rawLevel: level.rawValue)
    }

    // MARK: - Private
}
