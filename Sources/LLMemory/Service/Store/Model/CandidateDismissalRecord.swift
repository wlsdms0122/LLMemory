//
//  CandidateDismissalRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct CandidateDismissalRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case kind
        case dismissCount
        case wordCount
        case sectionCount
        case generation
        case reason
        case lastDismissedAt
    }

    // MARK: - Property
    let noteId: String
    let kind: String
    let dismissCount: Int
    let wordCount: Int
    let sectionCount: Int
    let generation: Int
    let reason: String?
    let lastDismissedAt: Int

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension CandidateDismissalRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "candidate_dismissals" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
