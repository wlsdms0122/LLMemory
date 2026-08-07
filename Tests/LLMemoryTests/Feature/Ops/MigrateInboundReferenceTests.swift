//
//  MigrateInboundReferenceTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// A reference edge is derived from the marker written in the body. Renaming the target cannot invent
// an edge the body does not spell — the referrer has to be told, and edit itself.
@Suite("MigrateInboundReference Tests", .serialized)
struct MigrateInboundReferenceTests {
    // MARK: - Property
    private let home: MemoryHome
    private let links: LinkGraph
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        links = LinkGraph(home)
    }
    
    // MARK: - Test
    @Test("migrating a referenced note drops the edge, flags the referrer, and keeps the marker visible")
    func migrateRepointsInboundReferenceAndFlagsReferrer() throws {
        // Given
        try home.reindexFile(at: try home.writeNoteFile(id: "target-note", body: "# body"))
        try home.reindexFile(at: try home.writeNoteFile(
            id: "referrer",
            body: "see [[target-note]] for context"
        ))
        
        #expect(try links.referenceEdges(from: "referrer", to: "target-note") == 1,
            "setup: referrer should reference target-note")
        
        // When
        let migrated = home.apply(["op": "migrate_note", "id": "target-note", "new_id": "new-note"])
        
        // Then
        #expect(migrated.status == "ok", "\(migrated.error)")
        #expect(try links.referenceEdges(from: "referrer", to: "new-note") == 0,
            "an edge the body does not spell must not be invented by the rename")
        #expect(try links.edges(pointingAt: "target-note") == 0, "no edge may point at the retired id")
        #expect(try links.markers(from: "referrer", to: "target-note") == 1,
            "the dangling citation must stay observable")
        #expect(try links.unresolvedStaleReferenceFlags(on: "referrer") == 1,
            "the referrer must be flagged stale_ref")
        
        // When — the referrer's body is corrected and reindexed.
        try home.reindexFile(at: try home.writeNoteFile(
            id: "referrer",
            body: "see [[new-note]] for context"
        ))
        
        // Then
        #expect(try links.referenceEdges(from: "referrer", to: "new-note") == 1,
            "the edge rematerializes once the body names the new id")
    }
}
