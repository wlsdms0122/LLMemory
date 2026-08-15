//
//  RecordEventTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Records an event row — best-effort by contract (a trace must not fail
// the operation it traces). The payload crosses in pre-serialized form so
// the transaction stays Sendable.
struct RecordEventTransaction: GRDBTransaction {
    // MARK: - Property
    let kind: String
    let payloadJSON: String
    let sessionId: SessionId?
    let ts: Int?

    // MARK: - Initializer
    init(kind: String, payload: [String: Any?], sessionId: SessionId? = nil, ts: Int? = nil) {
        self.init(
            kind: kind,
            payloadJSON: Events.serializePayload(payload),
            sessionId: sessionId,
            ts: ts
        )
    }

    init(kind: String, payloadJSON: String, sessionId: SessionId? = nil, ts: Int? = nil) {
        self.kind = kind
        self.payloadJSON = payloadJSON
        self.sessionId = sessionId
        self.ts = ts
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        Events.record(db, kind: kind, payloadJSON: payloadJSON, sessionId: sessionId, ts: ts)
    }

    // MARK: - Private
}
