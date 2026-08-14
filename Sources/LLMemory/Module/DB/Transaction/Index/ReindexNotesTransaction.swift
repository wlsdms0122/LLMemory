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
    let filePaths: [String]

    // MARK: - Initializer
    init(filePaths: [String]) {
        self.filePaths = filePaths
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Indexer.ReindexOutcome] {
        try Indexer.reindexFiles(db, filePaths: filePaths)
    }

    // MARK: - Private
}
