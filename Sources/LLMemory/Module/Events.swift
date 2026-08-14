//
//  Events.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

struct Events: Sendable {
    // MARK: - Property
    static let kindCapture = "capture"
    static let kindConsolidation = "consolidation"
    static let kindRetrieval = "retrieval"
    

    // MARK: - Initializer
    // MARK: - Public
    func record(
        _ db: Database,
        kind: String,
        payload: [String: Any?],
        sessionId: String? = nil,
        ts: Int? = nil
    ) {
        let timestamp = ts ?? Int(Date().timeIntervalSince1970)
        let json = serializePayload(payload)
        
        var record = EventRecord(ts: timestamp, kind: kind, sessionId: sessionId, payload: json)
        
        try? record.insert(db)
    }
    
    // A lone event INSERT is a single atomic statement — it needs no cross-process
    // write lock, so callers outside a locked section pass the queue directly.
    func record(
        _ queue: any DatabaseWriter,
        kind: String,
        payload: [String: Any?],
        sessionId: String? = nil,
        ts: Int? = nil
    ) {
        try? queue.write { db in
            record(db, kind: kind, payload: payload, sessionId: sessionId, ts: ts)
        }
    }
    
    func record(
        _ db: Database,
        kind: String,
        payloadJSON: String,
        sessionId: String? = nil,
        ts: Int? = nil
    ) {
        let timestamp = ts ?? Int(Date().timeIntervalSince1970)
        var record = EventRecord(ts: timestamp, kind: kind, sessionId: sessionId, payload: payloadJSON)

        try? record.insert(db)
    }

    func record(
        _ queue: any DatabaseWriter,
        kind: String,
        payloadJSON: String,
        sessionId: String? = nil,
        ts: Int? = nil
    ) {
        let timestamp = ts ?? Int(Date().timeIntervalSince1970)
        var record = EventRecord(ts: timestamp, kind: kind, sessionId: sessionId, payload: payloadJSON)
        
        try? queue.write { db in
            try record.insert(db)
        }
    }
    
    // Pre-serialization for retrieval side effects derived on the read path and
    // applied later by a write transaction.
    func retrievalPayloadJSON(cmd: String, payload: [(String, Any?)]) -> String {
        var fields: [String: Any?] = ["cmd": cmd]
        
        for (key, value) in payload { fields[key] = value }
        
        return serializePayload(fields)
    }
    
    
    // MARK: - Private
    func serializePayload(_ payload: [String: Any?]) -> String {
        let cleaned = payload.compactMapValues { value in value }
        
        if let data = try? JSONSerialization.data(withJSONObject: cleaned, options: []),
            let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        return "{}"
    }
}
