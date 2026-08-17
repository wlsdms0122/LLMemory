//
//  ApplyGeneValueOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// The one write path for a gene value: the catalog decides whether the
// value is admissible, and the row and its provenance event are written.
//
// It is an operation rather than a service call because every caller
// already holds a scope and needs the write inside their unit of work — an
// ops batch that is rejected later must not leave a gene changed. A service
// method taking a scope would say the same thing while pretending the work
// belongs a tier up.
struct ApplyGeneValueOperation: GRDBOperation {
    // MARK: - Property
    let geneId: String
    let value: Double
    let cause: String
    let detail: String?
    let requireMutable: Bool
    let ts: Int

    // What this brain's configuration says for the gene, if it says anything.
    // The old value falls back through it to the wild type, and reading a
    // config file is not something a database transaction does.
    let configured: Double?

    // MARK: - Initializer
    init(
        geneId: String,
        value: Double,
        cause: String,
        detail: String? = nil,
        requireMutable: Bool,
        ts: Int,
        configured: Double?
    ) {
        self.geneId = geneId
        self.value = value
        self.cause = cause
        self.detail = detail
        self.requireMutable = requireMutable
        self.ts = ts
        self.configured = configured
    }

    // MARK: - Public
    @discardableResult
    func execute(_ db: Database) throws -> (old: Double, new: Double) {
        if let rejection = Genes.rejection(geneId, value: value, requireMutable: requireMutable) {
            throw rejection
        }

        guard let gene = Genes.gene(geneId) else { throw GenomeWriteError.unknownGene(geneId) }

        let old = try FetchGeneValueOperation(geneId: geneId).execute(db)
            ?? configured ?? gene.wildType

        try SetGeneOperation(
            geneId: geneId,
            value: value,
            oldValue: old,
            cause: cause,
            detail: detail,
            ts: ts
        )
            .execute(db)

        return (old, value)
    }

    // MARK: - Private
}
