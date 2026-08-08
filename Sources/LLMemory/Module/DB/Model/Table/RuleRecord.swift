//
//  RuleRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

struct RuleRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case rulesetId
        case kind
        case params
        case enabled
    }

    // MARK: - Property
    let id: Int64
    let rulesetId: String
    let kind: String
    let params: String
    let enabled: Bool

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension RuleRecord: FetchableRecord, TableRecord {
    static var databaseTableName: String { "rule" }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
