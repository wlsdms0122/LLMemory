//
//  EventRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB

struct EventRecord: Encodable {
    enum CodingKeys: String, CodingKey {
        case ts
        case kind
        case sessionId
        case payload
    }

    // MARK: - Property
    private(set) var id: Int64?
    // Column types, not domain values. A table record mirrors the DDL by
    // hand and is tied to it by a round-trip test, so it holds what the
    // columns hold; EventKind, SessionId and EventPayload convert one level
    // up, in RecordEventTransaction, which is the only place that builds one.
    let ts: Int
    let kind: String
    let sessionId: String?
    let payload: String

    // MARK: - Initializer
    init(ts: Int, kind: String, sessionId: String?, payload: String) {
        self.ts = ts
        self.kind = kind
        self.sessionId = sessionId
        self.payload = payload
    }

    // MARK: - Lifecycle
}

extension EventRecord: MutablePersistableRecord {
    static var databaseTableName: String { "events" }
    static var databaseColumnEncodingStrategy: DatabaseColumnEncodingStrategy { .convertToSnakeCase }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        if id == nil {
            id = inserted.rowID
        }
    }
}
