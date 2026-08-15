//
//  Events.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

enum Events {
    // MARK: - Property
    static let kindCapture = "capture"
    static let kindConsolidation = "consolidation"
    static let kindRetrieval = "retrieval"
    

    // MARK: - Initializer
    // MARK: - Public
    static func record(
        _ db: Database,
        kind: String,
        payload: [String: Any?],
        sessionId: SessionId? = nil,
        ts: Int? = nil
    ) {
        let timestamp = ts ?? Int(Date().timeIntervalSince1970)
        let json = serializePayload(payload)
        
        var record = EventRecord(ts: timestamp, kind: kind, sessionId: sessionId?.rawValue, payload: json)
        
        try? record.insert(db)
    }
    
    // A lone event INSERT is a single atomic statement — it needs no cross-process
    // write lock, so callers outside a locked section pass the queue directly.
    static func record(
        _ queue: any DatabaseWriter,
        kind: String,
        payload: [String: Any?],
        sessionId: SessionId? = nil,
        ts: Int? = nil
    ) {
        try? queue.write { db in
            record(db, kind: kind, payload: payload, sessionId: sessionId, ts: ts)
        }
    }
    
    static func record(
        _ db: Database,
        kind: String,
        payloadJSON: String,
        sessionId: SessionId? = nil,
        ts: Int? = nil
    ) {
        let timestamp = ts ?? Int(Date().timeIntervalSince1970)
        var record = EventRecord(ts: timestamp, kind: kind, sessionId: sessionId?.rawValue, payload: payloadJSON)

        try? record.insert(db)
    }

    static func record(
        _ queue: any DatabaseWriter,
        kind: String,
        payloadJSON: String,
        sessionId: SessionId? = nil,
        ts: Int? = nil
    ) {
        let timestamp = ts ?? Int(Date().timeIntervalSince1970)
        var record = EventRecord(ts: timestamp, kind: kind, sessionId: sessionId?.rawValue, payload: payloadJSON)
        
        try? queue.write { db in
            try record.insert(db)
        }
    }
    
    // Pre-serialization for retrieval side effects derived on the read path and
    // applied later by a write transaction.
    static func retrievalPayloadJSON(cmd: String, payload: [(String, Any?)]) -> String {
        var fields: [String: Any?] = ["cmd": cmd]
        
        for (key, value) in payload { fields[key] = value }
        
        return serializePayload(fields)
    }
    
    
    // MARK: - Private
    static func serializePayload(_ payload: [String: Any?]) -> String {
        let cleaned = payload.compactMapValues { value in value }
        
        if let data = try? JSONSerialization.data(withJSONObject: cleaned, options: []),
            let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        return "{}"
    }
}
