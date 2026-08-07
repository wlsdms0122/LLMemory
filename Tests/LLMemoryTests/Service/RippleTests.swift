//
//  RippleTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// When a note changes, the notes that cite it need to hear about it. Only a written citation counts —
// a co-occurrence is a statistic, and flagging on it would bury the real signal.
@Suite("Ripple Tests", .serialized)
struct RippleTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("only an inbound reference is flagged — not an outbound one, and not a co-occurrence")
    func flagInboundReferrersFlagsOnlyInboundReference() throws {
        // Given
        try seedThreeNotes()
        try link("tmp-ripple-b", "tmp-ripple-a", kind: Links.kindReference)
        try link("tmp-ripple-a", "tmp-ripple-c", kind: Links.kindReference)
        try link("tmp-ripple-a", "tmp-ripple-c", kind: Links.kindCooccur)
        
        // When
        let flagged = try home.database().write { database in
            try Ripple.flagInboundReferrers(database, targetId: "tmp-ripple-a", reason: "test", now: home.now)
        }
        
        // Then
        let ids = try home.read { database in
            Set(try String.fetchAll(
                database,
                sql: "SELECT note_id FROM ripple_flags WHERE note_id LIKE 'tmp-ripple%'"
            ))
        }
        
        #expect(flagged == 1)
        #expect(ids == ["tmp-ripple-b"], "only the inbound reference referrer is flagged — got \(ids)")
    }
    
    @Test("a flagged note surfaces as a reconsolidation candidate")
    func rippleCandidatesReturned() throws {
        // Given
        try seedThreeNotes()
        try link("tmp-ripple-b", "tmp-ripple-a", kind: Links.kindReference)
        try flagReferrers(of: "tmp-ripple-a")
        
        // When
        let ids = try candidateIds()
        
        // Then
        #expect(ids.contains("tmp-ripple-b"))
    }
    
    @Test("a stale note stays off the reconsolidation surface even while flagged")
    func rippleCandidatesExcludeStaleNotes() throws {
        // Given
        try seedThreeNotes()
        try link("tmp-ripple-b", "tmp-ripple-a", kind: Links.kindReference)
        try link("tmp-ripple-c", "tmp-ripple-a", kind: Links.kindReference)
        try flagReferrers(of: "tmp-ripple-a")
        
        try home.database().write { database in
            try Notes.setStale(database, nid: "tmp-ripple-c", stale: true)
        }
        
        // When
        let ids = try candidateIds()
        
        // Then
        #expect(ids.contains("tmp-ripple-b"), "a fresh flagged note should still surface")
        #expect(!ids.contains("tmp-ripple-c"), "a stale flagged note must not surface")
    }
    
    // MARK: - Private
    // Rows are written straight in: the subject is which edges cause a flag, so the notes need to
    // exist but their bodies do not matter.
    private func seedThreeNotes() throws {
        try home.database().write { database in
            try database.execute(
                sql: "INSERT OR IGNORE INTO axes (axis, description, created_at) VALUES ('flow', 'flow', ?)",
                arguments: [home.now]
            )
            
            for noteId in ["tmp-ripple-a", "tmp-ripple-b", "tmp-ripple-c"] {
                try database.execute(sql: """
                    INSERT INTO notes (id, axis, path, title, summary, priority, file_mtime, indexed_at)
                    VALUES (?, 'flow', ?, ?, '', 'lazy', ?, ?)
                    """, arguments: [noteId, "tmp/\(noteId).md", noteId, home.now, home.now])
            }
        }
    }
    
    private func link(_ source: String, _ destination: String, kind: String) throws {
        try home.database().write { database in
            try database.execute(sql: """
                INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES (?, ?, ?, 1.0, ?, ?)
                """, arguments: [source, destination, kind, home.now, home.now])
        }
    }
    
    private func flagReferrers(of noteId: String) throws {
        _ = try home.database().write { database in
            try Ripple.flagInboundReferrers(database, targetId: noteId, reason: "test", now: home.now)
        }
    }
    
    private func candidateIds() throws -> Set<String> {
        try home.read { database in
            Set(try Candidates.rippleCandidates(database, limit: 50).map(\.id))
        }
    }
}
