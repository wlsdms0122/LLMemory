//
//  MetaRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct MetaRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case key
        case value
    }

    // MARK: - Property
    let key: String
    let value: String?

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension MetaRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "meta" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
