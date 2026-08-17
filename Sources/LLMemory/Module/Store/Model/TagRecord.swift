//
//  TagRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct TagRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case tag
    }

    // MARK: - Property
    let noteId: String
    let tag: String

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension TagRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "tags" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
