//
//  FetchGeneValueOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// This brain's stored value for one gene, or nil when it has none and reads
// as wild-type. Answered from the row rather than the process cache, so a
// write that follows another write in the same unit of work sees what that
// unit actually did.
struct FetchGeneValueOperation: GRDBReadOperation {
    // MARK: - Property
    let geneId: String

    // MARK: - Initializer
    init(geneId: String) {
        self.geneId = geneId
    }

    // MARK: - Public
    func execute(_ db: Database) throws -> Double? {
        try GenomeRecord.fetchOne(db, key: geneId)?.value
    }

    // MARK: - Private
}
