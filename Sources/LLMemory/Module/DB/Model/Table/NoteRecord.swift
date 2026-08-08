//
//  NoteRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct NoteRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case axis
        case path
        case title
        case summary
        case priority
        case fileMtime
        case indexedAt
        case editedAt
        case stale
        case template
        case locked
        case wordCount
        case sectionCount
        case contentHash
    }

    // MARK: - Property
    let id: String
    let axis: String
    let path: String
    let title: String
    let summary: String?
    let priority: String
    let fileMtime: Int
    let indexedAt: Int
    let editedAt: Int
    let stale: Bool
    let template: String?
    let locked: Bool
    let wordCount: Int
    let sectionCount: Int
    let contentHash: String

    // MARK: - Initializer
    // MARK: - Lifecycle
}

extension NoteRecord: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "notes" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }
}
