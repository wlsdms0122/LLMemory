//
//  FetchGenomeValuesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Genome-domain transactions — the DB vocabulary for the epigenome
// (per-brain gene values) and its provenance ledger.
struct FetchGenomeValuesTransaction: GRDBReadTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: Double] {
        try GenomeRecord.fetchAll(db)
            .reduce(into: [:]) { values, record in values[record.geneId] = record.value }
    }

    // MARK: - Private
}
