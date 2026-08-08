//
//  GenomeEventRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

struct GenomeEventRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case geneId
        case oldValue
        case newValue
        case cause
        case detail
        case ts
    }

    // MARK: - Property
    private(set) var id: Int64?
    let geneId: String
    let oldValue: Double?
    let newValue: Double
    let cause: String
    let detail: String?
    let ts: Int

    // MARK: - Initializer
    init(geneId: String, oldValue: Double?, newValue: Double, cause: String, detail: String?, ts: Int) {
        self.geneId = geneId
        self.oldValue = oldValue
        self.newValue = newValue
        self.cause = cause
        self.detail = detail
        self.ts = ts
    }

    // MARK: - Lifecycle
}

extension GenomeEventRecord: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "genome_events" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        if id == nil {
            id = inserted.rowID
        }
    }
}
