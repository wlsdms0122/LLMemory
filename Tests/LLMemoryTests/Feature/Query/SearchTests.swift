//
//  SearchTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("Search Tests", .serialized)
struct SearchTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a plain query becomes an OR over its tokens, so any one of them can match")
    func matchExprTokenizesToOR() {
        #expect(Search.ftsMatchExpr("alpha beta", raw: false) == "\"alpha\" OR \"beta\"")
    }
    
    @Test("a raw query is handed to FTS5 verbatim, operators and all")
    func matchExprRawPassesVerbatim() {
        #expect(Search.ftsMatchExpr("transfer NOT giro", raw: true) == "transfer NOT giro")
    }
    
    @Test("a query with no tokens is nil rather than an expression that matches everything")
    func matchExprEmptyIsNil() {
        #expect(Search.ftsMatchExpr("   ", raw: false) == nil)
        #expect(Search.ftsMatchExpr("", raw: true) == nil)
    }
    
    @Test("a multi-keyword query matches a note carrying any keyword, not the phrase")
    func multiKeywordQueryMatchesViaOR() throws {
        // Given
        #expect(create(
            id: "search-target",
            title: "iOS log masking Transformer structure",
            body: "## Structure\nthree PIIMaskingTransformer instances mask the line.\n"
        ).status == "ok")
        
        // When
        let hits = try home.read { database in
            try SearchNotesFTSTransaction(query: "log masking transformer").perform(database)
        }
        
        // Then
        #expect(hits.contains { hit in hit.id == "search-target" })
    }
    
    @Test("--raw lets an FTS5 NOT actually exclude a note")
    func rawHonorsFTS5Operators() throws {
        // Given
        #expect(create(id: "raw-both", title: "transfer giro both", body: "## A\ntransfer and giro\n").status == "ok")
        #expect(create(id: "raw-only", title: "transfer only", body: "## A\ntransfer here\n").status == "ok")
        
        // When
        let hits = try home.read { database in
            try SearchNotesFTSTransaction(query: "transfer NOT giro", raw: true).perform(database)
        }
        
        // Then
        let ids = Set(hits.map(\.id))
        
        #expect(ids.contains("raw-only"))
        #expect(!ids.contains("raw-both"))
    }
    
    @Test("a limit above the rerank pool still returns every match")
    func limitAboveThirtyReturnsAllMatches() throws {
        // Given
        for index in 0 ..< 35 {
            #expect(create(id: "pool-\(index)", title: "title", body: "## A\nquixotic pool token\n").status == "ok")
        }
        
        // When
        let hits = try home.read { database in
            try SearchNotesFTSTransaction(query: "quixotic pool", limit: 40).perform(database)
        }
        
        // Then
        #expect(hits.count == 35)
    }
    
    @Test("the fetch pool is wide enough to rerank, and exactly the limit when there is nothing to rerank")
    func fetchPoolSizeFollowsTheRerankNeed() {
        #expect(Search.fetchPoolSize(limit: 40, needsRerank: true) >= 40)
        #expect(Search.fetchPoolSize(limit: 5, needsRerank: true) == 15)
        #expect(Search.fetchPoolSize(limit: 40, needsRerank: false) == 40)
    }
    
    @Test("a malformed raw query throws a named error instead of leaking the SQLite one")
    func rawMalformedThrowsCleanError() throws {
        // Given
        #expect(create(id: "rawerr-note", title: "transfer", body: "## A\ntransfer\n").status == "ok")
        
        // Then
        try home.read { database in
            #expect(throws: Search.SearchError.self) {
                _ = try SearchNotesFTSTransaction(query: "transfer \"", raw: true).perform(database)
            }
        }
    }
    
    @Test("a stray operator in a non-raw query is text, not syntax — the search still answers")
    func nonRawNeverThrowsOnStrayOperators() throws {
        // Given
        #expect(create(id: "safe-note", title: "transfer", body: "## A\ntransfer\n").status == "ok")
        
        // When
        let hits = try home.read { database in try SearchNotesFTSTransaction(query: "transfer \"").perform(database) }
        
        // Then
        #expect(hits.contains { hit in hit.id == "safe-note" })
    }
    
    // MARK: - Private
    private func create(id: String, title: String, body: String) -> OperationsEngine.Result {
        home.createNote(id: id, axis: "tech", title: title, tags: ["tech"], content: body)
    }
}
