//
//  Genome.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Genome-domain transactions — the DB vocabulary for the epigenome
// (per-brain gene values) and its provenance ledger.
struct FetchGenomeValuesTransaction: GRDBTransaction {
    // MARK: - Initializer
    init() { }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String: Double] {
        try GenomeRecord.fetchAll(db)
            .reduce(into: [:]) { values, record in values[record.geneId] = record.value }
    }

    // MARK: - Private
}

struct FetchGenomeEventsTransaction: GRDBTransaction {
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

struct SetGeneTransaction: GRDBTransaction {
    // MARK: - Property
    let geneId: String
    let value: Double
    let oldValue: Double?
    let cause: String
    let detail: String?
    let ts: Int

    // MARK: - Initializer
    init(
        geneId: String,
        value: Double,
        oldValue: Double?,
        cause: String,
        detail: String?,
        ts: Int
    ) {
        self.geneId = geneId
        self.value = value
        self.oldValue = oldValue
        self.cause = cause
        self.detail = detail
        self.ts = ts
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        try GenomeRecord(geneId: geneId, value: value, updatedAt: ts).upsert(db)

        var event = GenomeEventRecord(
            geneId: geneId,
            oldValue: oldValue,
            newValue: value,
            cause: cause,
            detail: detail,
            ts: ts
        )
        try event.insert(db)
    }

    // MARK: - Private
}

struct ResetGeneTransaction: GRDBTransaction {
    // MARK: - Property
    let geneId: String
    let oldValue: Double?
    let wildType: Double
    let cause: String
    let ts: Int

    // MARK: - Initializer
    init(
        geneId: String,
        oldValue: Double?,
        wildType: Double,
        cause: String,
        ts: Int
    ) {
        self.geneId = geneId
        self.oldValue = oldValue
        self.wildType = wildType
        self.cause = cause
        self.ts = ts
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        _ = try GenomeRecord.deleteOne(db, key: geneId)

        var event = GenomeEventRecord(
            geneId: geneId,
            oldValue: oldValue,
            newValue: wildType,
            cause: cause,
            detail: "reset to wild-type",
            ts: ts
        )
        try event.insert(db)
    }

    // MARK: - Private
}
