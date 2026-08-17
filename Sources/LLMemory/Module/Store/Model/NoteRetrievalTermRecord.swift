//
//  NoteRetrievalTermRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct NoteRetrievalTermRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case noteId
        case kind
        case term
        case status
        case provenance
        case rejectReason
        case createdAt
        case validatedAt
    }

    // MARK: - Property
    let noteId: String
    let kind: String
    let term: String
    let status: String
    let provenance: String?
    let rejectReason: String?
    let createdAt: Int
    let validatedAt: Int?

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteRetrievalTermRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "note_retrieval_terms" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
