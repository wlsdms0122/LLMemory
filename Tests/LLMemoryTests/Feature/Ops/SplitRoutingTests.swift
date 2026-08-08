//
//  SplitRoutingTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Splitting a note has to decide where its non-recoverable artifacts go. Anything the caller has not
// routed is a conflict rather than a guess, and a conflict rolls the whole split back.
@Suite("SplitRouting Tests", .serialized)
struct SplitRoutingTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("overlapping section claims are rejected before any file is touched")
    func overlappingSectionsRejectedBeforeFileWork() throws {
        // Given
        home.createNote(id: "src", content: "## A\nalpha\n### B\nbeta\n## C\ngamma\n")
        
        // When — the first child claims a subtree the second already owns.
        let result = home.apply(["op": "split_note", "from_id": "src", "into": [
            [
                "id": "rt-a", "axis": "flow", "title": "A", "tags": ["flow"], "summary": "summary",
                "sections": ["## A", "## A > ### B"]
            ],
            [
                "id": "rt-b", "axis": "flow", "title": "C", "tags": ["flow"], "summary": "summary",
                "sections": ["## C"]
            ]
        ]])
        
        // Then
        #expect(result.status == "rejected", "overlapping sections must be rejected, got \(result.status)")
        #expect(try childCount() == 0, "a rejected split must not create any child")
        #expect(try noteCount(id: "src") == 1, "the source must survive a rejected split")
    }
    
    @Test("an unrouted learned edge is a conflict — the split does not guess where it belongs")
    func unroutedAssocReturnsConflict() throws {
        // Given
        try seedSourceAndNeighbor()
        try seedAssocEdge()
        
        // When
        let result = split()
        
        // Then
        #expect(result.status == "conflict")
        #expect(result.conflict?.unresolved.contains { item in
            item.type == "link" && item.kind == "assoc" && item.neighbor == "nbr"
        } == true)
        #expect(try childCount() == 0, "a conflict must not partially apply the split")
        #expect(try noteCount(id: "src") == 1)
    }
    
    @Test("a routed edge lands on the chosen child alone, keeping its full learned weight")
    func assocRoutedToChosenChildKeepsFullWeight() throws {
        // Given
        try seedSourceAndNeighbor()
        try seedAssocEdge(weight: 0.7)
        
        // When
        let result = split(routing: [
            ["type": "link", "kind": "assoc", "neighbor": "nbr", "to": ["rt-a"]]
        ])
        
        // Then
        let weight = try home.read { database in
            try Double.fetchOne(database, sql: """
                SELECT weight FROM note_links WHERE kind='assoc' AND (src='rt-a' OR dst='rt-a')
                """) ?? -1
        }
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(try assocEdges(touching: "rt-a") > 0, "the routed edge is not on the chosen child")
        #expect(try assocEdges(touching: "rt-b") == 0, "the edge leaked to a child it was not routed to")
        #expect(weight > 0.6, "a routed copy keeps the full learned weight (0.7), not weight/share (0.35)")
    }
    
    @Test("routing an edge to no child drops it rather than sending it somewhere")
    func droppedAssocVanishes() throws {
        // Given
        try seedSourceAndNeighbor()
        try seedAssocEdge()
        
        // When
        let result = split(routing: [["type": "link", "kind": "assoc", "neighbor": "nbr", "to": []]])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try assocEdges(touching: "rt-a") == 0)
        #expect(try assocEdges(touching: "rt-b") == 0)
    }
    
    @Test("keeping the source does not excuse an artifact no child covers")
    func keepWithEmptyRemainderStillConflictsOnUncovered() throws {
        // Given
        try seedSourceAndNeighbor()
        try seedReviewMeta()
        
        // When
        let result = home.apply([
            "op": "split_note", "from_id": "src", "into": children, "remainder": ["keep": true]
        ])
        
        // Then
        #expect(result.status == "conflict",
            "keep:true with an empty remainder must still conflict on an uncovered artifact")
        #expect(result.conflict?.unresolved.contains { item in
            item.type == "meta" && item.key == "status"
        } == true)
        #expect(try metaCount(noteId: "src") == 1, "a conflict must roll back, leaving the source's meta intact")
    }
    
    @Test("a lineage edge drops without a conflict — it states a fact about the source, not the children")
    func lineageLinkDropsWithoutConflict() throws {
        // Given
        try seedSourceAndNeighbor()
        try home.database().write { database in
            try database.execute(sql: """
                INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES ('src', 'nbr', 'supersedes', 1.0, 1, 1)
                """)
        }
        
        // When
        let result = split()
        
        // Then
        let synthesized = try home.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM note_links WHERE kind='supersedes'
                  AND (src IN ('rt-a','rt-b') OR dst IN ('rt-a','rt-b'))
                """) ?? 0
        }
        
        #expect(result.status == "ok", "a lineage link must not raise a conflict — it drops")
        #expect(synthesized == 0, "a lineage edge must not be synthesized onto the children")
    }
    
    @Test("routed metadata arrives verbatim on the chosen child and nowhere else")
    func metaRoutedVerbatim() throws {
        // Given
        try seedSourceAndNeighbor()
        try seedReviewMeta()
        
        // When
        let result = split(routing: [
            ["type": "meta", "namespace": "review", "key": "status", "to": ["rt-a"]]
        ])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try reviewStatus(of: "rt-a") == "approved", "routed meta must arrive verbatim")
        #expect(try reviewStatus(of: "rt-b") == nil, "meta must not appear on the unrouted child")
    }
    
    // MARK: - Private
    private var children: [[String: Any]] {
        [
            [
                "id": "rt-a", "axis": "flow", "title": "A", "tags": ["flow"],
                "summary": "summary", "sections": ["## A"]
            ],
            [
                "id": "rt-b", "axis": "flow", "title": "B", "tags": ["flow"],
                "summary": "summary", "sections": ["## B"]
            ]
        ]
    }
    
    @discardableResult
    private func split(routing: [[String: Any]]? = nil) -> OpsTransaction.Result {
        var operation: [String: Any] = ["op": "split_note", "from_id": "src", "into": children]
        
        if let routing { operation["routing"] = routing }
        
        return home.apply(operation)
    }
    
    private func seedSourceAndNeighbor() throws {
        home.createNote(id: "src", content: "## A\nalpha\n## B\nbeta\n")
        home.createNote(id: "nbr", content: "## X\nneighbor\n")
    }
    
    private func seedAssocEdge(weight: Double = 0.7) throws {
        try home.database().write { database in
            try database.execute(sql: """
                INSERT OR IGNORE INTO note_links
                    (src, dst, kind, weight, created_at, last_activated_at, provenance)
                VALUES ('nbr', 'src', 'assoc', ?, 1, 1, 'p')
                """, arguments: [weight])
        }
    }
    
    private func seedReviewMeta() throws {
        let result = home.apply([
            "op": "set_note_meta", "id": "src", "namespace": "review", "key": "status", "value": "approved"
        ])
        
        #expect(result.status == "ok", "\(result.error)")
    }
    
    private func childCount() throws -> Int {
        try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes WHERE id IN ('rt-a','rt-b')") ?? 0
        }
    }
    
    private func noteCount(id: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes WHERE id = ?", arguments: [id]) ?? 0
        }
    }
    
    private func assocEdges(touching noteId: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM note_links WHERE kind='assoc' AND (src = ? OR dst = ?)
                """, arguments: [noteId, noteId]) ?? 0
        }
    }
    
    private func metaCount(noteId: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM note_meta WHERE note_id = ? AND key='status'",
                arguments: [noteId]
            ) ?? 0
        }
    }
    
    private func reviewStatus(of noteId: String) throws -> String? {
        try home.read { database in
            try String.fetchOne(database, sql: """
                SELECT value FROM note_meta WHERE note_id = ? AND namespace='review' AND key='status'
                """, arguments: [noteId])
        }
    }
}
