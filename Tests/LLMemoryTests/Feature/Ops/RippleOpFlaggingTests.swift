//
//  RippleOpFlaggingTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// When a note changes shape, the notes that cite it by name are now wrong and have to be told. A
// co-occurrence neighbour is not wrong — flagging it too turns the signal into noise.
@Suite("RippleOpFlagging Tests", .serialized)
struct RippleOpFlaggingTests {
    // MARK: - Property
    private let home: MemoryHome
    private let links: LinkGraph
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        links = LinkGraph(home)
    }
    
    // MARK: - Test
    @Test("splitting a note flags the note that cites it, and leaves its co-occurrence neighbour alone")
    func splitFlagsInboundReferrerNotCooccurNeighbor() throws {
        // Given
        try seed(target: "rof-src", targetBody: "## A\nalpha\n## B\nbeta\n",
            referrer: "rof-referrer", neighbor: "rof-nbr")
        
        #expect(try links.unresolvedStaleReferenceFlags(on: "rof-referrer") == 0, "precondition")
        
        // When
        let result = home.apply(["op": "split_note", "from_id": "rof-src", "into": [
            ["id": "rof-a", "axis": "flow", "title": "A", "tags": ["flow"], "summary": "summary", "sections": ["## A"]],
            ["id": "rof-b", "axis": "flow", "title": "B", "tags": ["flow"], "summary": "summary", "sections": ["## B"]]
        ]])
        
        // Then
        #expect(result.status == "ok", "split failed: \(result.error)")
        #expect(try links.unresolvedStaleReferenceFlags(on: "rof-referrer") == 1,
            "the note citing the split source must be flagged stale_ref")
        #expect(try links.unresolvedStaleReferenceFlags(on: "rof-nbr") == 0,
            "a co-occurrence neighbour must not be flagged")
    }
    
    @Test("merging flags whoever cited the absorbed note, not the survivor's co-occurrence neighbour")
    func mergeFlagsFromReferrerNotIntoCooccurNeighbor() throws {
        // Given — the survivor exists first, so the neighbour can co-occur with it.
        try home.reindexFile(at: try home.writeNoteFile(id: "rof-into", body: "# into\n"))
        try seed(target: "rof-from", targetBody: "# from\n",
            referrer: "rof-mref", neighbor: "rof-mnbr", neighborOf: "rof-into")
        
        // When
        let result = home.apply([
            "op": "merge_notes", "into_id": "rof-into", "from_ids": ["rof-from"],
            "merged_content": "## body\nmerged\n", "summary": "summary", "tags": ["flow"]
        ])
        
        // Then
        #expect(result.status == "ok", "merge failed: \(result.error)")
        #expect(try links.unresolvedStaleReferenceFlags(on: "rof-mref") == 1,
            "the note citing the merged-away note must be flagged stale_ref")
        #expect(try links.unresolvedStaleReferenceFlags(on: "rof-mnbr") == 0,
            "the survivor's co-occurrence neighbour must not be flagged")
    }
    
    @Test("invalidating a note flags whoever cited it, and leaves its co-occurrence neighbour alone")
    func invalidateFlagsInboundReferrerNotCooccurNeighbor() throws {
        // Given
        try seed(target: "rof-inv", targetBody: "# target\n",
            referrer: "rof-iref", neighbor: "rof-inbr")
        
        // When
        let result = home.apply(["op": "invalidate", "id": "rof-inv", "reason": "superseded"])
        
        // Then
        #expect(result.status == "ok", "invalidate failed: \(result.error)")
        #expect(try links.unresolvedStaleReferenceFlags(on: "rof-iref") == 1,
            "the note citing the invalidated note must be flagged stale_ref")
        #expect(try links.unresolvedStaleReferenceFlags(on: "rof-inbr") == 0,
            "a co-occurrence neighbour must not be flagged")
    }
    
    // MARK: - Private
    private func seed(
        target: String,
        targetBody: String,
        referrer: String,
        neighbor: String,
        neighborOf: String? = nil
    ) throws {
        try home.reindexFile(at: try home.writeNoteFile(id: target, body: targetBody))
        try home.reindexFile(at: try home.writeNoteFile(
            id: referrer,
            body: "## X\nsee [[\(target)]] for context\n"
        ))
        try home.reindexFile(at: try home.writeNoteFile(id: neighbor, body: "## N\nneighbor\n"))
        
        try home.database().write { database in
            try database.execute(sql: """
                INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES (?, ?, 'cooccur', 0.5, 1, 1)
                """, arguments: [neighbor, neighborOf ?? target])
        }
    }
}
