//
//  RippleFlagRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct RippleFlagRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case flag
        case reason
        case createdAt
        case lastFlaggedAt
        case flagCount
        case resolvedAt
    }

    // MARK: - Property
    let noteId: String
    let flag: String
    let reason: String?
    let createdAt: Int
    let lastFlaggedAt: Int
    let flagCount: Int
    let resolvedAt: Int?

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension RippleFlagRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "ripple_flags" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
