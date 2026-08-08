//
//  NoteLinkRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct NoteLinkRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case src
        case dst
        case kind
        case weight
        case createdAt
        case lastActivatedAt
        case provenance
    }

    // MARK: - Property
    let src: String
    let dst: String
    let kind: String
    let weight: Double
    let createdAt: Int
    let lastActivatedAt: Int
    let provenance: String?

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteLinkRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "note_links" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
