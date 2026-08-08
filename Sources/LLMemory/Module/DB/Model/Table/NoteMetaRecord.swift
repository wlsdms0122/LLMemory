//
//  NoteMetaRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

struct NoteMetaRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case namespace
        case key
        case value
        case updatedAt
    }

    // MARK: - Property
    let noteId: String
    let namespace: String
    let key: String
    let value: String
    let updatedAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteMetaRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "note_meta" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
