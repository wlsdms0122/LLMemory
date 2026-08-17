//
//  NoteVectorRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct NoteVectorRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case dim
        case vec
        case builtAt
    }

    // MARK: - Property
    let noteId: String
    let dim: Int
    let vec: Data
    let builtAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteVectorRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "note_vectors" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
