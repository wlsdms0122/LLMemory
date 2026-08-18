//
//  SetGeneOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SetGeneOperation: GRDBOperation {
    // MARK: - Property
    typealias Parameter = (String, Double, Double?, String, String?, Int)
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
    func execute(_ db: Database) throws {
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
