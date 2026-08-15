//
//  ApplyGeneValueTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// The one write path for a gene value: the catalog decides whether the
// value is admissible, the row and its provenance event are written, and
// the process cache is primed with what was just written.
//
// It is a transaction rather than a service call because every caller
// already holds a scope and needs this inside their unit of work — an ops
// batch that is rejected later must not leave a gene changed. A service
// method taking a scope would say the same thing while pretending the
// work belongs a tier up.
struct ApplyGeneValueTransaction: GRDBTransaction {
    // MARK: - Property
    let geneId: String
    let value: Double
    let cause: String
    let detail: String?
    let requireMutable: Bool
    let ts: Int

    // MARK: - Initializer
    init(
        geneId: String,
        value: Double,
        cause: String,
        detail: String? = nil,
        requireMutable: Bool,
        ts: Int
    ) {
        self.geneId = geneId
        self.value = value
        self.cause = cause
        self.detail = detail
        self.requireMutable = requireMutable
        self.ts = ts
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database) throws -> (old: Double, new: Double) {
        guard let gene = Genes.gene(geneId) else {
            throw GenomeWriteError.unknownGene(geneId)
        }

        if requireMutable && !gene.mutable {
            throw GenomeWriteError.locked(geneId)
        }

        guard value >= gene.min && value <= gene.max else {
            throw GenomeWriteError.outOfBounds(geneId, value, gene)
        }

        if gene.integer && value != value.rounded() {
            throw GenomeWriteError.notInteger(geneId, value)
        }

        let old = Genes.cached(geneId) ?? Config.getDouble(geneId, default: gene.wildType)

        try SetGeneTransaction(
            geneId: geneId,
            value: value,
            oldValue: old,
            cause: cause,
            detail: detail,
            ts: ts
        )
            .perform(db)

        Genes.prime(geneId, value)

        return (old, value)
    }

    // MARK: - Private
}
