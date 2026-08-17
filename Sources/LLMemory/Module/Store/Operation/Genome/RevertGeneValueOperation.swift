//
//  RevertGeneValueOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Drops this brain's value for a gene so it answers as wild-type again,
// recording what it was. The counterpart of ApplyGeneValueOperation and
// scoped the same way — the revert belongs to the caller's unit of work.
struct RevertGeneValueOperation: GRDBOperation {
    // MARK: - Property
    let geneId: String
    let cause: String
    let ts: Int

    // What this brain's configuration says for the gene, if it says anything.
    // The old value falls back through it to the wild type.
    let configured: Double?

    // MARK: - Initializer
    init(geneId: String, cause: String, ts: Int, configured: Double?) {
        self.geneId = geneId
        self.cause = cause
        self.ts = ts
        self.configured = configured
    }

    // MARK: - Public
    @discardableResult
    func execute(_ db: Database) throws -> Double {
        if let rejection = Genes.rejection(geneId, value: nil) { throw rejection }

        guard let gene = Genes.gene(geneId) else { throw GenomeWriteError.unknownGene(geneId) }

        let old = try FetchGeneValueOperation(geneId: geneId).execute(db)
            ?? configured ?? gene.wildType

        try ResetGeneOperation(
            geneId: geneId,
            oldValue: old,
            wildType: gene.wildType,
            cause: cause,
            ts: ts
        )
            .execute(db)

        return old
    }

    // MARK: - Private
}
