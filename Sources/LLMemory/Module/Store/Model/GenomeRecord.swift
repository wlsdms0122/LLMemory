//
//  GenomeRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

struct GenomeRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case geneId
        case value
        case updatedAt
    }

    // MARK: - Property
    let geneId: String
    let value: Double
    let updatedAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension GenomeRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "genome" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
