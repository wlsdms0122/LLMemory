//
//  NoteDeletionTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Deleting a note is guarded by what still points at it. A citation someone wrote is a reason to stop
// and ask; an edge the system learned by itself is not.
@Suite("NoteDeletion Tests", .serialized)
struct NoteDeletionTests {
    // MARK: - Property
    private let home: MemoryHome
    private let lifecycle: NoteLifecycle
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        lifecycle = NoteLifecycle(home)
    }
    
    // MARK: - Test
    @Test("deleting a note takes its file and its rows with it")
    func deleteRemovesFileAndRows() throws {
        // Given
        lifecycle.create("tdb-del1", axis: "tdbaxis")
        
        let file = try home.indexedPath(of: "tdb-del1")
        
        #expect(FileManager.default.fileExists(atPath: file.path))
        
        // When
        let result = home.apply(["op": "delete_note", "id": "tdb-del1", "reason": "test cleanup"])
        
        // Then
        let remaining = try home.read { database in
            try Int.fetchOne(database, sql: "SELECT 1 FROM notes WHERE id = 'tdb-del1'")
        }
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(remaining == nil)
    }
    
    @Test("a learned edge does not block a delete — nobody wrote it, so nobody is losing a citation")
    func deleteIsNotBlockedByLearnedInboundEdge() throws {
        // Given
        lifecycle.create("tdl-1", axis: "tdbaxis")
        lifecycle.create("tdl-2", axis: "tdbaxis")
        
        try home.database().write { database in
            for kind in ["cooccur", "assoc"] {
                try database.execute(sql: """
                    INSERT OR REPLACE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                    VALUES (?, ?, ?, 1.0, ?, ?)
                    """, arguments: ["tdl-1", "tdl-2", kind, home.now, home.now])
            }
        }
        
        // When
        let result = home.apply(["op": "delete_note", "id": "tdl-2", "reason": "test"])
        
        // Then
        #expect(result.status == "ok", "a learned inbound edge must not block a delete: \(result.error)")
    }
    
    @Test("a written citation blocks the delete until the caller says force, and then no edge is left")
    func deleteInboundLinkBlocksUnlessForce() throws {
        // Given
        lifecycle.create("tdb-d1", axis: "tdbaxis")
        lifecycle.create("tdb-d2", axis: "tdbaxis")
        
        try home.database().write { database in
            try database.execute(sql: """
                INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES (?, ?, 'reference', 1.0, ?, ?)
                """, arguments: ["tdb-d2", "tdb-d1", home.now, home.now])
        }
        
        // When
        let withoutForce = home.apply(["op": "delete_note", "id": "tdb-d1", "reason": "test"])
        let withForce = home.apply([
            "op": "delete_note", "id": "tdb-d1", "reason": "test", "force": true
        ])
        
        // Then
        let remaining = try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM note_links WHERE src = 'tdb-d1' OR dst = 'tdb-d1'"
            ) ?? 0
        }
        
        #expect(withoutForce.status != "ok")
        #expect(withForce.status == "ok", "\(withForce.error)")
        #expect(remaining == 0, "the forced delete left a dangling edge")
    }
    
    @Test("every member of a sibling family is guarded, not just the one the sort order reaches first")
    func deleteGuardProtectsEverySibling() throws {
        // Given
        let family = ["aaa-frag", "mmm-frag", "zzz-frag"]
        
        for noteId in family { lifecycle.create(noteId, axis: "tdbaxis") }
        
        try home.database().write { database in
            try Links.linkSiblings(database, ids: family, now: home.now)
        }
        
        // Then
        for noteId in family {
            let result = home.apply(["op": "delete_note", "id": noteId, "reason": "test"])
            
            #expect(result.status != "ok", "sibling \(noteId) was deleted without force")
        }
        
        // When
        let forced = home.apply(["op": "delete_note", "id": "aaa-frag", "reason": "test", "force": true])
        
        // Then
        #expect(forced.status == "ok", "\(forced.error)")
    }
}
