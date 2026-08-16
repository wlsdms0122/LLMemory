//
//  ActivityWindowRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct ActivityWindowRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case endedAt
        case label
        case queryCount
    }

    // MARK: - Property
    private(set) var id: Int64?
    let startedAt: Int
    let endedAt: Int
    let label: String?
    let queryCount: Int

    // MARK: - Initializer
    init(startedAt: Int, endedAt: Int, label: String?, queryCount: Int) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.label = label
        self.queryCount = queryCount
    }

    // MARK: - Lifecycle
}

extension ActivityWindowRecord: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "activity_windows" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        if id == nil {
            id = inserted.rowID
        }
    }
}
