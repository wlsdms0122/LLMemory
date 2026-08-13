//
//  NoteExtraRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/13/26.
//

import Foundation
import GRDB

struct NoteExtraRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case key
        case value
    }

    // MARK: - Property
    let noteId: String
    let key: String
    let value: String

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteExtraRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "note_extra" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
