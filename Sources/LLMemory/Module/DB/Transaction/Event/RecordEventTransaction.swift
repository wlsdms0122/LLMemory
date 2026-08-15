//
//  RecordEventTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// Writes an event row — the one way one gets written. Best-effort by
// contract: a trace must not fail the operation it traces, so a refused
// insert is swallowed here rather than left for every caller to swallow
// its own way.
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
            kind: kind,
            sessionId: sessionId?.rawValue,
            payload: payload.json
        )

        try? record.insert(db)
    }

    // MARK: - Private
}
