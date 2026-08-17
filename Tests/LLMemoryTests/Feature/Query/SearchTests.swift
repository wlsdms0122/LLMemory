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
        #expect(FTSMatch.text("alpha beta", keywords: FrequencyKeywordExtractor()).expression == "\"alpha\" OR \"beta\"")
    }
    
    @Test("a raw query is handed to FTS5 verbatim, operators and all")
    func matchExprRawPassesVerbatim() {
        #expect(FTSMatch.raw("transfer NOT giro").expression == "transfer NOT giro")
    }
    
    @Test("a query with no tokens is nil rather than an expression that matches everything")
    func matchExprEmptyIsNil() {
        #expect(FTSMatch.text("   ", keywords: FrequencyKeywordExtractor()).expression == nil)
        #expect(FTSMatch.raw("").expression == nil)
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
            try SearchNotesFTSOperation(match: .text("log masking transformer", keywords: FrequencyKeywordExtractor()), primingWindowMin: home.retrievalTuning.primingWindowMin, primingAlpha: home.retrievalTuning.primingAlpha).execute(database)
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
            try SearchNotesFTSOperation(match: .raw("transfer NOT giro"), primingWindowMin: home.retrievalTuning.primingWindowMin, primingAlpha: home.retrievalTuning.primingAlpha).execute(database)
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
            try SearchNotesFTSOperation(match: .text("quixotic pool", keywords: FrequencyKeywordExtractor()), limit: 40, primingWindowMin: home.retrievalTuning.primingWindowMin, primingAlpha: home.retrievalTuning.primingAlpha).execute(database)
        }
        
        // Then
        #expect(hits.count == 35)
    }
    
    @Test("the fetch pool is wide enough to rerank, and exactly the limit when there is nothing to rerank")
    func fetchPoolSizeFollowsTheRerankNeed() {
        #expect(TagPriorRerank.poolSize(limit: 40, needsRerank: true) >= 40)
        #expect(TagPriorRerank.poolSize(limit: 5, needsRerank: true) == 15)
        #expect(TagPriorRerank.poolSize(limit: 40, needsRerank: false) == 40)
    }
    
    @Test("a malformed raw query throws a named error instead of leaking the SQLite one")
    func rawMalformedThrowsCleanError() throws {
        // Given
        #expect(create(id: "rawerr-note", title: "transfer", body: "## A\ntransfer\n").status == "ok")
        
        // Then
        try home.read { database in
            #expect(throws: FTSMatchError.self) {
                _ = try SearchNotesFTSOperation(match: .raw("transfer \""), primingWindowMin: home.retrievalTuning.primingWindowMin, primingAlpha: home.retrievalTuning.primingAlpha).execute(database)
            }
        }
    }
    
    @Test("a stray operator in a non-raw query is text, not syntax — the search still answers")
    func nonRawNeverThrowsOnStrayOperators() throws {
        // Given
        #expect(create(id: "safe-note", title: "transfer", body: "## A\ntransfer\n").status == "ok")
        
        // When
        let hits = try home.read { database in try SearchNotesFTSOperation(match: .text("transfer \"", keywords: FrequencyKeywordExtractor()), primingWindowMin: home.retrievalTuning.primingWindowMin, primingAlpha: home.retrievalTuning.primingAlpha).execute(database) }
        
        // Then
        #expect(hits.contains { hit in hit.id == "safe-note" })
    }

    @Test("the search reads its cues through whichever reader it was given")
    func searchUsesTheInjectedKeywordReader() throws {
        // Given — the note is findable only by a word the query never contains,
        // so a hit proves the substituted reader is the one that was consulted.
        #expect(create(id: "swap-note", title: "quokka", body: "## A\nquokka\n").status == "ok")

        struct FixedKeywords: KeywordExtracting {
            func keywords(in text: String, limit: Int) -> [String] { ["quokka"] }
        }

        // When
        let hits = try home.read { database in
            try SearchNotesFTSOperation(match: .text("nothing to do with it", keywords: FixedKeywords()), primingWindowMin: home.retrievalTuning.primingWindowMin, primingAlpha: home.retrievalTuning.primingAlpha)
                .execute(database)
        }

        // Then
        #expect(hits.contains { hit in hit.id == "swap-note" })
    }

    // MARK: - Private
    private func create(id: String, title: String, body: String) -> OperationsResult {
        home.createNote(id: id, title: title, tags: ["tech"], content: body)
    }
}
