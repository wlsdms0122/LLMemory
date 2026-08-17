//
//  CheckIntegrityOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct CheckIntegrityOperation: GRDBReadOperation {
    // MARK: - Property
    let brain: BrainContext
    let level: Indexer.IntegrityLevel

    private let indexer = Indexer()

    // MARK: - Initializer
    init(brain: BrainContext, level: Indexer.IntegrityLevel = .l1) {
        self.brain = brain
        self.level = level
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> (ok: Bool, msgs: [String]) {
        try indexer.check(db, brain, rawLevel: level.rawValue)
    }

    // MARK: - Private
}
