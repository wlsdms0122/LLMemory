//
//  SearchAssocRehearsalTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("SearchAssocRehearsal Tests", .serialized)
struct SearchAssocRehearsalTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    // An assoc edge decays on every prune. If co-surfacing through search does not strengthen it, an
    // edge that only ever appears that way is guaranteed to be pruned away.
    @Test("co-surfacing two notes in one search strengthens the assoc edge between them")
    func searchRehearsesExistingAssocEdge() throws {
        // Given
        home.createNote(id: "areh-a", title: "alpha", content: "## A\nzephyrquasar context\n")
        home.createNote(id: "areh-b", title: "beta", content: "## A\nzephyrquasar context\n")
        
        _ = try home.database().write { db in
            try StrengthenLinksTransaction(
                pairs: [("areh-a", "areh-b")],
                kind: Links.kindAssoc,
                step: 0.5,
                cap: 1.0
            )
                .perform(db)
        }
        
        #expect(try assocWeight(between: "areh-a", and: "areh-b") == 0.5)
        
        // When
        let outcome = try home.readScope { scope in try home.retrievalService.search(
                scope,
                query: "zephyrquasar",
                tags: [],
                limit: 5,
                expand: 0,
                sessionId: nil,
                includeStale: false,
                excludeTags: nil,
                sinceTs: nil,
                raw: false
            ) }
        
        try home.database().write { db in _ = try RecordRetrievalTransaction(outcome.record).perform(db) }
        
        // Then
        #expect(try assocWeight(between: "areh-a", and: "areh-b") ?? 0 > 0.5,
            "search did not rehearse the edge, so it can only ever decay")
    }
    
    // MARK: - Private
    private func assocWeight(between first: String, and second: String) throws -> Double? {
        try home.read { database in
            try Double.fetchOne(database, sql: """
                SELECT weight FROM note_links WHERE kind = ? AND
                  ((src = ? AND dst = ?) OR (src = ? AND dst = ?))
                """, arguments: [Links.kindAssoc, first, second, second, first])
        }
    }
}
