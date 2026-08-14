//
//  FetchGenomeEventsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FetchGenomeEventsTransaction: GRDBReadTransaction {
    // MARK: - Property
    let geneId: String?
    let limit: Int

    // MARK: - Initializer
    init(geneId: String?, limit: Int) {
        self.geneId = geneId
        self.limit = limit
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [GenomeEventRecord] {
        var request = GenomeEventRecord
            .order(Column("ts").desc, Column("id").desc)
            .limit(limit)

        if let geneId {
            request = request.filter(Column("gene_id") == geneId)
        }

        return try request.fetchAll(db)
    }

    // MARK: - Private
}
