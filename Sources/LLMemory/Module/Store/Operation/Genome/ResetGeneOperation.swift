//
//  ResetGeneOperation.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct ResetGeneOperation: GRDBOperation {
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
    func execute(_ db: Database) throws {
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
