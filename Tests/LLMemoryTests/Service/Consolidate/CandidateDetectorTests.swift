//
//  CandidateDetectorTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Candidate surfaces propose work to do. A note that is off the surface — stale, or deliberately
// invalidated — must not be proposed, and an eager note must not be invalidated out from under the boot.
@Suite("CandidateDetector Tests", .serialized)
struct CandidatesTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private let detector = CandidateDetector()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("invalidate refuses an eager note — the boot set cannot be emptied by a candidate sweep")
    func invalidateOpRejectsEagerNote() {
        // Given
        let created = home.createNote(
            id: "cand-inv-eager1",
            title: "eager protected",
            content: "## A\nbody\n",
            fields: ["priority": "eager"]
        )
        
        #expect(created.status == "ok", "failed to create the eager note: \(created.error)")
        
        // When
        let result = home.apply(["op": "invalidate", "id": "cand-inv-eager1", "reason": "should be blocked"])
        
        // Then
        #expect(result.status != "ok", "invalidate was allowed on an eager note — the handler guard is missing")
    }
    
    @Test("neighbors leaves a stale note off the surface")
    func neighborsExcludesStale() throws {
        // Given
        let keyword = "nbrtesttoken"
        let shared = "## A\n\(keyword) shared body content\n"
        
        home.createNote(id: "nbr-seed", title: keyword, content: shared)
        
        for index in 0 ..< 3 {
            home.createNote(id: "nbr-act-\(index)", title: "\(keyword) active \(index)", content: shared)
        }
        
        home.createNote(id: "nbr-stale", title: "\(keyword) stale", content: shared)
        
        try markStale(ids: ["nbr-stale"])
        
        // When
        let hits = try home.readScope { scope in
            try detector.neighbors(scope, noteId: "nbr-seed", k: 10)
        }
        
        // Then
        let ids = Set(hits.map(\.id))
        
        #expect(!ids.contains("nbr-stale"), "a stale note surfaced as a neighbour")
        #expect(ids.contains { id in id.hasPrefix("nbr-act-") },
            "no active neighbour surfaced — the baseline itself is broken")
    }
    
    @Test("near-duplicate detection leaves a stale note off the surface")
    func nearDuplicatesExcludeStale() throws {
        // Given
        let body = "## A\nndupsharedtoken alpha beta gamma delta epsilon shared identical body\n"
        
        for id in ["ndup-a", "ndup-b", "ndup-stale"] {
            home.createNote(id: id, title: "ndupsharedtoken doc", content: body)
        }
        
        try markStale(ids: ["ndup-stale"])
        
        // When
        let duplicates = try home.readScope { scope in
            try detector.nearDuplicates(scope, limit: 50)
        }
        
        // Then
        let touched = Set(duplicates.flatMap { pair in [pair.a.id, pair.b.id] })
        
        #expect(!touched.contains("ndup-stale"), "a stale note surfaced as a near-duplicate candidate")
        #expect(touched.contains("ndup-a") && touched.contains("ndup-b"),
            "the active pair was not found — the baseline itself is broken")
    }
    
    @Test("a note whose only edge points off the surface counts as unlinked, so it can be proposed again")
    func missingEdgeFtsFallbackWhenOnlyNeighborsOffSurface() throws {
        // Given
        let shared = "## A\ndeadedgetoken zephyr quasar nimbus vortex shared distinctive body\n"
        
        try create(id: "dead-a", title: "deadedgetoken doc", content: shared)
        try create(id: "dead-b", content: "## A\nplain unrelated filler\n")
        try create(id: "dead-c", tag: "tech", title: "deadedgetoken doc", content: shared)
        try create(id: "dead-d", tag: "tech", content: "## A\nother filler entirely\n")
        
        let invalidated = home.apply(["op": "invalidate", "id": "dead-b", "reason": "test"])
        
        #expect(invalidated.status == "ok", "invalidate failed: \(invalidated.error)")
        
        // When
        let edges = try home.readScope { scope in
            try detector.missingEdges(scope, limit: 20, perNote: 3, ftsBm25: -0.1)
        }
        
        // Then
        let pairs = Set(edges.map { edge in "\(edge.a.id)|\(edge.b.id)" })
        #expect(pairs.contains("dead-a|dead-c"),
            "dead-a's only edge points at an invalidated note, so it should count as degree 0")
    }
    
    // MARK: - Private
    private func create(id: String, tag: String = "flow", title: String = "title", content: String) throws {
        let result = home.createNote(id: id, title: title, tags: [tag], content: content)
        
        guard result.status == "ok" else { throw TestFailure("failed to create \(id): \(result.error)") }
    }
    
    private func markStale(ids: [String]) throws {
        try home.database().write { database in
            for id in ids {
                try database.execute(
                    sql: "UPDATE notes SET stale = 1 WHERE id = ?",
                    arguments: [id]
                )
            }
        }
    }
}
