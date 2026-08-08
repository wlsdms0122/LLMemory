//
//  EntityIndexRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct EntityIndexRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case entity
        case noteId
        case lastSeenAt
        case hitCount
    }

    // MARK: - Property
    let entity: String
    let noteId: String
    let lastSeenAt: Int
    let hitCount: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension EntityIndexRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "entity_index" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
