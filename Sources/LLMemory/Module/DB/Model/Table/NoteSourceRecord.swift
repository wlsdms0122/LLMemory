//
//  NoteSourceRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct NoteSourceRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case sourceHash
        case sourceCheckedAt
        case sourceStale
        case declHash
    }

    // MARK: - Property
    let noteId: String
    let sourceHash: String?
    let sourceCheckedAt: Int
    let sourceStale: Bool
    let declHash: String?

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteSourceRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "note_source" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
