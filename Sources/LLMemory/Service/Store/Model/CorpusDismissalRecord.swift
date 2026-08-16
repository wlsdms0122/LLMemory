//
//  CorpusDismissalRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct CorpusDismissalRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case targetKey
        case kind
        case dismissCount
        case generation
        case reason
        case lastDismissedAt
    }

    // MARK: - Property
    let targetKey: String
    let kind: String
    let dismissCount: Int
    let generation: Int
    let reason: String?
    let lastDismissedAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension CorpusDismissalRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "corpus_dismissals" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
