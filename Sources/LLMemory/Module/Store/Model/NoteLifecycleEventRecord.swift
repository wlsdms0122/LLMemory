//
//  NoteLifecycleEventRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct NoteLifecycleEventRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case noteId
        case kind
        case reason
        case createdAt
    }

    // MARK: - Property
    private(set) var id: Int64?
    let noteId: String
    let kind: String
    let reason: String?
    let createdAt: Int

    // MARK: - Initializer
    init(noteId: String, kind: String, reason: String?, createdAt: Int) {
        self.noteId = noteId
        self.kind = kind
        self.reason = reason
        self.createdAt = createdAt
    }

    // MARK: - Lifecycle
}

extension NoteLifecycleEventRecord: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "note_lifecycle_events" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        if id == nil {
            id = inserted.rowID
        }
    }
}
