//
//  SectionAttributionTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import GRDB
@testable import LLMemory

// A hit says which section matched, so the caller can read that part instead of the whole note. The
// index is per section, which also keeps a long multi-topic note from being penalised for its length.
@Suite("SectionAttribution Tests", .serialized)
struct SectionAttributionTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a hit names the section whose body actually matched")
    func searchAttributesBestMatchingSection() throws {
        // Given
        #expect(create("runbook", title: "runbook", body: """
            intro
            ## Slack
            slack message payload
            ## GitHub
            zyqqar pull request review
            """).status == "ok")
        
        // When
        let hit = try hit(for: "zyqqar", in: "runbook")
        
        // Then
        #expect(hit != nil)
        #expect(hit?.section == "## GitHub")
    }
    
    @Test("a match on the title alone names no section — there is none to point at")
    func headOnlyMatchHasNilSection() throws {
        // Given
        #expect(home.createNote(
            id: "head-note", title: "wibblezork special title",
            tags: ["tech"], content: "## A\nplain body\n"
        ).status == "ok")
        
        // When
        let hit = try hit(for: "wibblezork", in: "head-note")
        
        // Then
        #expect(hit != nil)
        #expect(hit?.section == nil)
    }
    
    @Test("a note matching in two sections is still one hit, not two")
    func multiSectionMatchYieldsSingleRow() throws {
        // Given
        #expect(create("multi", title: "multi", body: "## A\nfloopdar here\n## B\nfloopdar there\n")
            .status == "ok")
        
        // When
        let hits = try search("floopdar")
        
        // Then
        #expect(hits.filter { hit in hit.id == "multi" }.count == 1)
    }
    
    @Test("a section of a long note competes on its own terms against a short dedicated note")
    func longNoteSectionCompetesWithShortNote() throws {
        // Given
        let filler = (1 ... 40)
            .map { index in "unrelated filler line \(index) about other topics" }
            .joined(separator: "\n")
        
        #expect(create("long-multi", title: "long",
            body: "## Other\n\(filler)\n## Target\nglorpnik payload glorpnik\n").status == "ok")
        #expect(create("short-dedicated", title: "short", body: "## Only\nglorpnik once\n").status == "ok")
        
        // When
        let hits = try search("glorpnik")
        
        // Then
        #expect(hits.first?.id == "long-multi", "length alone must not sink a strongly matching section")
        #expect(hits.first?.section == "## Target")
    }
    
    @Test("evidence from different sections accumulates — two tokens beat one")
    func crossSectionEvidenceAccumulates() throws {
        // Given
        #expect(create("xsec-multi", title: "runbook",
            body: "## A\nqorvath send payload formats\n## B\nzelnar gate policy roles\n").status == "ok")
        #expect(create("xsec-decoy", title: "digest",
            body: "## X\nqorvath mentioned briefly\n").status == "ok")
        
        for index in 1 ... 8 {
            #expect(create("xsec-filler-\(index)", title: "filler \(index)",
                body: "## F\nunrelated topic words entirely \(index)\n").status == "ok")
        }
        
        // When
        let ids = try search("qorvath zelnar").map(\.id)
        
        // Then
        #expect(ids.first == "xsec-multi",
            "a note carrying both tokens must outrank a decoy carrying one — got \(ids)")
    }
    
    @Test("the similar surface carries the section too, not only search")
    func similarCarriesSection() throws {
        // Given
        #expect(create("sim-note", title: "sim", body: "## Alpha\nnothing\n## Beta\nqwombat data\n")
            .status == "ok")
        
        // When
        let hit = try home.read { database in
            try FetchSimilarNotesTransaction(keywords: ["qwombat"], limit: 5).perform(database)
                .first { similar in similar.id == "sim-note" }
        }
        
        // Then
        #expect(hit != nil)
        #expect(hit?.section == "## Beta")
    }
    
    // MARK: - Private
    @discardableResult
    private func create(_ id: String, title: String, body: String) -> OperationsResult {
        home.createNote(id: id, title: title, tags: ["tech"], content: body)
    }
    
    private func search(_ query: String) throws -> [SearchRow] {
        try home.read { database in try SearchNotesFTSTransaction(query: query, keywords: FrequencyKeywords()).perform(database) }
    }
    
    private func hit(for query: String, in noteId: String) throws -> SearchRow? {
        try search(query).first { hit in hit.id == noteId }
    }
}
