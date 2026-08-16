//
//  NoteUsageRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct NoteUsageRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case hitCount
        case lastRetrievedAt
        case createdAt
    }

    // MARK: - Property
    let noteId: String
    let hitCount: Int
    let lastRetrievedAt: Int
    let createdAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteUsageRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "note_usage" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
