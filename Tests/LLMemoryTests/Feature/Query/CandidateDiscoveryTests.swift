//
//  CandidateDiscoveryTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("CandidateDiscovery Tests", .serialized)
struct CandidateDiscoveryTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private var detector: CandidateDetector { CandidateDetector(brain: home.brain) }

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("notes that share an entity form a cluster")
    func sharedEntityFormsACluster() throws {
        // Given
        seedEntityGroup(count: 4)
        
        // When
        let clusters = try home.readScope { db in
            try detector.clusters(db, minSize: 2, maxSize: 50, limit: 20)
        }
        
        // Then
        #expect(clusters.contains { cluster in
            cluster.size >= 4 && cluster.members.contains { member in member.id.hasPrefix("clc-") }
        }, "four notes sharing one entity should come back as one component")
    }
    
    @Test("maxSize drops a component instead of returning a truncated one")
    func clustersDropOversizedComponents() throws {
        // Given
        seedEntityGroup(count: 4)
        
        // When
        let capped = try home.readScope { db in
            try detector.clusters(db, maxSize: 3, limit: 20)
        }
        
        // Then
        #expect(capped.allSatisfy { cluster in cluster.size <= 3 })
        #expect(!capped.contains { cluster in
            cluster.members.contains { member in member.id.hasPrefix("clc-") }
        }, "the 4-member component is over the cap, so it is dropped rather than trimmed")
    }
    
    @Test("two notes with the same body surface as a near-duplicate pair")
    func nearDuplicatesSurfaceMatchingBodies() throws {
        // Given
        let body = "## Structure\nthe transfer service applies the masking transformer to every log line\n"
        
        home.createNote(id: "dup-a", title: "A", tags: ["tech"], content: body)
        home.createNote(id: "dup-b", title: "B", tags: ["tech"], content: body)
        
        // When
        let duplicates = try home.readScope { db in
            try detector.nearDuplicates(db, limit: 20)
        }
        
        // Then
        #expect(duplicates.contains { pair in
            Set([pair.a.id, pair.b.id]) == ["dup-a", "dup-b"]
        }, "identical bodies are the clearest near-duplicate there is")
    }
    
    @Test("a cold pair sharing a rare token is a missing edge, and stops being one once linked")
    func missingEdgeSurfacesThenExcludesLinkedPair() throws {
        // Given
        let shared = "zalgonics qwertium flibberwock"
        
        home.createNote(id: "me-a", title: "A", tags: ["tech"], content: "## A\n\(shared) alpha\n")
        home.createNote(id: "me-b", title: "B", tags: ["tech"], content: "## B\n\(shared) beta\n")
        home.createNote(id: "me-c", title: "C", tags: ["tech"], content: "## C\nunrelated ziffle\n")
        
        try home.database().write { database in try database.execute(sql: "DELETE FROM note_links") }
        
        // Then
        #expect(try missingEdgeHoldsTheSeededPair(), "a cold pair sharing a rare token is a missing edge")
        
        // When
        try home.database().write { database in
            try database.execute(sql: """
                INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES ('me-a','me-b','assoc',0.5,?,?)
                """, arguments: [home.now, home.now])
        }
        
        // Then
        #expect(try !missingEdgeHoldsTheSeededPair(), "an already-linked pair is no longer missing an edge")
    }
    
    @Test("neighbors refuses an anchor that does not exist rather than returning nothing")
    func neighborsRefusesAnUnknownAnchor() throws {
        #expect(throws: (any Error).self) {
            try home.readScope { db in try detector.neighbors(db, noteId: "nonexistent-xyz", k: 5) }
        }
    }
    
    @Test("near_duplicate is a retrieval kind the CLI accepts")
    func nearDuplicateKindRegistered() {
        #expect(CandidateDetector.retrievalKinds.contains("near_duplicate"))
        #expect(CandidateDetector.validKinds.contains("near_duplicate"))
    }
    
    @Test("missing_edge replaced graph_isolates — the retired kind is gone, not aliased")
    func missingEdgeKindRegistered() {
        #expect(CandidateDetector.retrievalKinds.contains("missing_edge"))
        #expect(CandidateDetector.validKinds.contains("missing_edge"))
        #expect(!CandidateDetector.validKinds.contains("graph_isolates"))
    }
    
    // MARK: - Private
    private func seedEntityGroup(count: Int) {
        for index in 1 ... count {
            home.createNote(
                id: "clc-\(index)",
                title: "title \(index)",
                content: "## S\nbody \(index)\n",
                fields: ["entities": ["sharedEntity"]]
            )
        }
    }
    
    private func missingEdgeHoldsTheSeededPair() throws -> Bool {
        try home.readScope { db in
            let edges = try detector.missingEdges(db, limit: 20, ftsBm25: 0.0)
            
            return edges.contains { edge in Set([edge.a.id, edge.b.id]) == ["me-a", "me-b"] }
        }
    }
}
