//
//  RevertGeneValueTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Drops this brain's value for a gene so it answers as wild-type again,
// recording what it was. The counterpart of ApplyGeneValueTransaction and
// scoped the same way — the revert belongs to the caller's unit of work.
struct RevertGeneValueTransaction: GRDBTransaction {
    // MARK: - Property
    let geneId: String
    let cause: String
    let ts: Int

    // MARK: - Initializer
    init(geneId: String, cause: String, ts: Int) {
        self.geneId = geneId
        self.cause = cause
        self.ts = ts
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> Double {
        if let rejection = Genes.rejection(geneId, value: nil) { throw rejection }

        guard let gene = Genes.gene(geneId) else { throw GenomeWriteError.unknownGene(geneId) }

        let old = Genes.cached(geneId) ?? Config.getDouble(geneId, default: gene.wildType)

        try ResetGeneTransaction(
            geneId: geneId,
            oldValue: old,
            wildType: gene.wildType,
            cause: cause,
            ts: ts
        )
            .perform(db)

        Genes.prime(geneId, nil)

        return old
    }

    // MARK: - Private
}
