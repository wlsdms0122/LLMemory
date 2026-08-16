//
//  ReindexNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ReindexNotesTransaction: GRDBTransaction {
    // MARK: - Property
    let brain: BrainContext
    let filePaths: [String]

    private let indexer = Indexer()

    // MARK: - Initializer
    init(brain: BrainContext, filePaths: [String]) {
        self.brain = brain
        self.filePaths = filePaths
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Indexer.ReindexOutcome] {
        try indexer.reindexFiles(db, brain, filePaths: filePaths)
    }

    // MARK: - Private
}
