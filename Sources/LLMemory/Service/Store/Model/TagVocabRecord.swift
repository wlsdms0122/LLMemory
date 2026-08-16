//
//  TagVocabRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct TagVocabRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case tag
        case createdAt
    }

    // MARK: - Property
    let tag: String
    let createdAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension TagVocabRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "tag_vocab" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
