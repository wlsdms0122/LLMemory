//
//  ActivationTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("Activation Tests", .serialized)
struct ActivationTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    private static func recordRetrieval(
        _ db: Database, timestamp: Int, sessionId: String?, hitIds: [String], command: String = "search"
    ) throws {
        let payload: [String: Any] = ["cmd": command, "hit_ids": hitIds, "expand_ids": []]
        let json = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        
        try db.execute(
            sql: "INSERT INTO events (ts, kind, session_id, payload) VALUES (?, 'retrieval', ?, ?)",
            arguments: [timestamp, sessionId, json])
    }
    
    @Test("anonymous events cluster by gap; labeled events group by label")
    func windowInference() throws {
        // Given
        home.createNote(id: "n1")
        home.createNote(id: "n2")
        
        let base = 1_000_000
        
        try home.database().write { database in
            try recordRetrieval(database, timestamp: base, sessionId: nil, hitIds: ["n1"])
            try recordRetrieval(database, timestamp: base + 60, sessionId: nil, hitIds: ["n2"])
            try recordRetrieval(database, timestamp: base + 60 + home.activationTuning.windowGapSec + 1,
                sessionId: nil, hitIds: ["n1"])
            try recordRetrieval(database, timestamp: base, sessionId: "task-a", hitIds: ["n1"])
            try recordRetrieval(database, timestamp: base + 90_000, sessionId: "task-a", hitIds: ["n2"])
        
        // When
            let result = try DeriveActivityWindowsOperation(now: base + 100_000, windowGapSec: home.activationTuning.windowGapSec).execute(database)
        
        // Then
            #expect(result.eventsConsumed == 5)
            #expect(result.hitsRecorded == 5)
        }
        
        try home.read { database in
            let anonymous = try Int.fetchOne(
                database, sql: "SELECT COUNT(*) FROM activity_windows WHERE label IS NULL") ?? 0
            let labeled = try Int.fetchOne(
                database, sql: "SELECT COUNT(*) FROM activity_windows WHERE label = 'task-a'") ?? 0
            
            #expect(anonymous == 2)
            #expect(labeled == 2)
        }
    }
    
    @Test("derivation is watermarked — a second run consumes nothing")
    func watermarkExactlyOnce() throws {
        // Given
        home.createNote(id: "n1")
        
        
        try home.database().write { database in
            try recordRetrieval(database, timestamp: 2_000_000, sessionId: nil, hitIds: ["n1"])
        
        // When
            let first = try DeriveActivityWindowsOperation(now: 2_000_100, windowGapSec: home.activationTuning.windowGapSec).execute(database)
        
        // Then
            #expect(first.eventsConsumed == 1)
            
            let second = try DeriveActivityWindowsOperation(now: 2_000_200, windowGapSec: home.activationTuning.windowGapSec).execute(database)
            
            #expect(second.eventsConsumed == 0)
            
            let hits = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM retrieval_hits") ?? 0
            
            #expect(hits == 1)
        }
    }
    
    @Test("integrate derives the trace before compacting the raw events it came from")
    func integrateDerivesBeforeCompaction() throws {
        // Given
        home.createNote(id: "n1")
        
        let old = home.now - 40 * 86_400
        
        try home.write { database in
            try recordRetrieval(database, timestamp: old, sessionId: nil, hitIds: ["n1"])
        }
        
        _ = try home.database().write { db in try home.consolidateService.integrate(db) }
        
        // When
        try home.read { database in
            let rawLeft = try Int.fetchOne(
                database, sql: "SELECT COUNT(*) FROM events WHERE kind = 'retrieval' AND ts = ?",
                arguments: [old]) ?? 0
            let hits = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM retrieval_hits") ?? 0
        
        // Then
            #expect(rawLeft == 0)
            #expect(hits == 1)
        }
    }
    
    @Test("mark_used: reported without response, content_overlap gated by response text")
    func markUsedSignals() throws {
        // Given
        home.createNote(id: "transfer-flow", title: "Transfer flow", summary: "the transfer flow")
        home.createNote(id: "unrelated-note", title: "Zebra topic", summary: "completely different")
        
        let now = home.now
        
        try home.database().write { database in
            try recordRetrieval(database, timestamp: now - 60, sessionId: nil,
                hitIds: ["transfer-flow", "unrelated-note"])
            
            _ = try DeriveActivityWindowsOperation(now: now, windowGapSec: home.activationTuning.windowGapSec).execute(database)
        }
        
        // When
        let reportedResult = home.apply(["op": "mark_used", "ids": ["transfer-flow"]])
        
        // Then
        #expect(reportedResult.status == "ok")
        
        let overlapResult = home.apply([
            "op": "mark_used", "ids": ["unrelated-note"],
            "response": "the answer quoted the body of unrelated-note here"
        ])
        
        #expect(overlapResult.status == "ok")
        
        try home.read { database in
            let reported = try String.fetchOne(database, sql: """
                SELECT used_signal FROM retrieval_hits WHERE note_id = 'transfer-flow'
                """)
            let overlap = try String.fetchOne(database, sql: """
                SELECT used_signal FROM retrieval_hits WHERE note_id = 'unrelated-note'
                """)
            
            #expect(reported == "reported")
            #expect(overlap == "content_overlap")
        }
    }
    
    @Test("mark_used rejects a note never surfaced in the lookback")
    func markUsedRejectsUnobserved() throws {
        // Given
        home.createNote(id: "never-surfaced")
        
        // When
        let result = home.apply(["op": "mark_used", "ids": ["never-surfaced"]])
        
        // Then
        #expect(result.status != "ok")
    }
    
    @Test("labeled mark_used never falls back to another session's hits (time inversion)")
    func markUsedLabelScoped() throws {
        // Given
        home.createNote(id: "answer-note")
        home.createNote(id: "snapshot-only-note")
        
        let now = home.now
        
        try home.database().write { database in
            try recordRetrieval(database, timestamp: now - 120, sessionId: "turn-1", hitIds: ["answer-note"])
            try recordRetrieval(database, timestamp: now - 10, sessionId: "turn-1:capture",
                hitIds: ["snapshot-only-note"])
            
            _ = try DeriveActivityWindowsOperation(now: now, windowGapSec: home.activationTuning.windowGapSec).execute(database)
        
        // When
            // A labeled mark attaches to the window with that label, and to no other.
            let ok = try MarkNotesUsedOperation(ids: ["answer-note"], response: nil,
                sessionLabel: SessionId("turn-1"), now: now, lookbackSec: home.activationTuning.usedLookbackSec).execute(database)
        
        // Then
            #expect(ok.first?.signal == "reported")
            #expect(throws: Activation.UsedError.self) {
                _ = try MarkNotesUsedOperation(ids: ["snapshot-only-note"], response: nil,
                    sessionLabel: SessionId("turn-1"), now: now, lookbackSec: home.activationTuning.usedLookbackSec).execute(database)
            }
        }
    }
    
    @Test("overall stats carry the activation section")
    func statsActivationSection() throws {
        // Given
        home.createNote(id: "n1")
        
        let now = home.now
        
        try home.database().write { database in
            try recordRetrieval(database, timestamp: now - 30, sessionId: "w1", hitIds: ["n1"])
            
            _ = try DeriveActivityWindowsOperation(now: now, windowGapSec: home.activationTuning.windowGapSec).execute(database)
        }
        
        // When
        let stats = try home.read { database in try OverallStatsOperation().execute(database) }
        
        // Then
        #expect(stats.activation.windows == 1)
        #expect(stats.activation.labeledWindows == 1)
        #expect(stats.activation.surfaced == 1)
        #expect(stats.activation.used == 0)
    }
    
    // MARK: - Private
    // Retrieval events are the raw signal the activation trace is derived from. Written straight in so
    // a test can lay down a shaped history without performing the retrievals that produced it.
    private func recordRetrieval(
        _ database: Database,
        timestamp: Int,
        sessionId: String?,
        hitIds: [String],
        command: String = "search"
    ) throws {
        let payload: [String: Any] = ["cmd": command, "hit_ids": hitIds, "expand_ids": []]
        let json = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        
        try database.execute(
            sql: "INSERT INTO events (ts, kind, session_id, payload) VALUES (?, 'retrieval', ?, ?)",
            arguments: [timestamp, sessionId, json]
        )
    }
}
