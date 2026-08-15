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
    let ts: Int
    let kind: String
    // The stored column, not the domain value — SessionId converts at this
    // boundary so nothing below can invent a second spelling of "no session".
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
