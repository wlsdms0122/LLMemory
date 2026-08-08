//
//  RetrievalHitRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

struct RetrievalHitRecord: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case windowId
        case noteId
        case surfacedAt
        case cmd
        case surfaceKind
        case usedSignal
        case usedAt
    }

    // MARK: - Property
    private(set) var id: Int64?
    let windowId: Int64
    let noteId: String
    let surfacedAt: Int
    let cmd: String
    let surfaceKind: String
    let usedSignal: String?
    let usedAt: Int?

    // MARK: - Initializer
    init(
        windowId: Int64,
        noteId: String,
        surfacedAt: Int,
        cmd: String,
        surfaceKind: String,
        usedSignal: String?,
        usedAt: Int?
    ) {
        self.windowId = windowId
        self.noteId = noteId
        self.surfacedAt = surfacedAt
        self.cmd = cmd
        self.surfaceKind = surfaceKind
        self.usedSignal = usedSignal
        self.usedAt = usedAt
    }

    // MARK: - Lifecycle
}

extension RetrievalHitRecord: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "retrieval_hits" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }
    static var databaseColumnDecodingStrategy: DatabaseColumnDecodingStrategy { .convertFromSnakeCase }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        if id == nil {
            id = inserted.rowID
        }
    }
}
