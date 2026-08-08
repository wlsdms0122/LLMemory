//
//  TagAliasRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct TagAliasRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case alias
        case canonical
        case createdAt
    }

    // MARK: - Property
    let alias: String
    let canonical: String
    let createdAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension TagAliasRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "tag_aliases" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
