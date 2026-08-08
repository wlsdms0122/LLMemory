//
//  RulesetRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

struct RulesetRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
    }

    // MARK: - Property
    let id: String
    let name: String
    let description: String?

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension RulesetRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "ruleset" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
