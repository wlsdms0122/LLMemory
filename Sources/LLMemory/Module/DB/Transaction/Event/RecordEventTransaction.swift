//
//  RecordEventTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Writes an event row — the one way one gets written. Whether a refused
// insert matters is not this transaction's to decide: a trace must not fail
// the operation it traces, but "must not fail it" and "must not be noticed"
// are different contracts, and only the caller knows which one it wants.
// So the failure comes back out, and each caller says what it does with it.
struct RecordEventTransaction: GRDBTransaction {
    // MARK: - Property
    let kind: EventKind
    let payload: EventPayload
    let sessionId: SessionId?
    // Absent means "now" — a caller that already fixed a clock for the work
    // being traced passes that instant so the trace lands inside it.
    let ts: Int?

    // MARK: - Initializer
    init(kind: EventKind, payload: EventPayload, sessionId: SessionId? = nil, ts: Int? = nil) {
        self.kind = kind
        self.payload = payload
        self.sessionId = sessionId
        self.ts = ts
    }

    // MARK: - Public
    func perform(_ db: Database) throws {
        var record = EventRecord(
            ts: ts ?? Int(Date().timeIntervalSince1970),
            kind: kind.rawValue,
            sessionId: sessionId?.rawValue,
            payload: payload.json
        )

        try record.insert(db)
    }

    // MARK: - Private
}
