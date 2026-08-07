//
//  DeleteInboundReferenceTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("DeleteInboundReference Tests", .serialized)
struct DeleteInboundReferenceTests {
    // MARK: - Property
    private let home: MemoryHome
    private let links: LinkGraph
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        links = LinkGraph(home)
    }
    
    // MARK: - Test
    @Test("deleting a referenced note leaves no dangling edge and flags whoever cited it")
    func deleteFlagsInboundReferenceReferrer() throws {
        // Given
        try home.reindexFile(at: try home.writeNoteFile(id: "target-note", body: "# body"))
        try home.reindexFile(at: try home.writeNoteFile(
            id: "referrer",
            body: "see [[target-note]] for context"
        ))
        
        #expect(try links.referenceEdges(from: "referrer", to: "target-note") == 1,
            "setup: referrer should reference target-note")
        
        // When
        let deleted = home.apply([
            "op": "delete_note", "id": "target-note", "reason": "test", "force": true
        ])
        
        // Then
        #expect(deleted.status == "ok", "\(deleted.error)")
        #expect(try links.edges(pointingAt: "target-note") == 0, "no edge may point at the deleted id")
        #expect(try links.unresolvedStaleReferenceFlags(on: "referrer") == 1,
            "the referrer must be flagged stale_ref once its target is gone")
    }
}
