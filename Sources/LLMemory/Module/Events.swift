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
        kind: String,
        txDB db: Database? = nil,
        payload: [String: Any?],
        sessionId: String? = nil,
        ts: Int? = nil
    ) {
        let timestamp = ts ?? Int(Date().timeIntervalSince1970)
        let json = serializePayload(payload)
        
        do {
            if let db {
                try db.execute(
                    sql: "INSERT INTO events (ts, kind, session_id, payload) VALUES (?, ?, ?, ?)",
                    arguments: [timestamp, kind, sessionId, json]
                )
            } else {
                try GRDBStorage.session.write { db in
                    try db.execute(
                        sql: "INSERT INTO events (ts, kind, session_id, payload) VALUES (?, ?, ?, ?)",
                        arguments: [timestamp, kind, sessionId, json]
                    )
                }
            }
        } catch {
        }
    }
    
    static func recordRetrieval(
        cmd: String,
        payload: [(String, Any?)],
        sessionId: String? = nil
    ) {
        var fields: [String: Any?] = ["cmd": cmd]
        
        for (key, value) in payload { fields[key] = value }
        
        record(kind: kindRetrieval, payload: fields, sessionId: sessionId)
    }
    
    // MARK: - Private
    private static func serializePayload(_ payload: [String: Any?]) -> String {
        let cleaned = payload.compactMapValues { value in value }
        
        if let data = try? JSONSerialization.data(withJSONObject: cleaned, options: []),
            let json = String(data: data, encoding: .utf8) {
            return json
        }
        
        return "{}"
    }
}
