//
//  AxisRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct AxisRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case axis
        case description
        case createdAt
    }

    // MARK: - Property
    let axis: String
    let description: String?
    let createdAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension AxisRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "axes" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
