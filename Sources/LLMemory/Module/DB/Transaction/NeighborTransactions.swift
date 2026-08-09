//
//  NeighborTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct FetchNeighborScoresTransaction: GRDBTransaction {
    // MARK: - Property
    let noteId: String
    let k: Int

    // MARK: - Initializer
    init(noteId: String, k: Int) {
        self.noteId = noteId
        self.k = k
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [Candidates.NeighborScore] {
        try Candidates.neighbors(db, noteId: noteId, k: k)
    }

    // MARK: - Private
}
