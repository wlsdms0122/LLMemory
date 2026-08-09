//
//  FtsMetaOnlyTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import GRDB
@testable import LLMemory

// A meta-only projection keeps a note findable by title and summary while taking its body out of the
// index. Both halves matter: one head row must remain, and the body must stop matching.
@Suite("FtsMetaOnly Tests", .serialized)
struct FtsMetaOnlyTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a meta-only projection collapses the note to exactly one head row")
    func metaOnlyProjectionKeepsHeadRowSentinel() throws {
        // Given
        #expect(home.createNote(
            id: "meta-note",
            axis: "tech",
            tags: ["tech"],
            content: "## A\nbody\n"
        ).status == "ok")
        
        // When
        try projectMetaOnly(id: "meta-note")
        
        // Then
        try home.read { database in
            let total = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM notes_fts WHERE id = 'meta-note'"
            ) ?? -1
            let head = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM notes_fts WHERE id = 'meta-note' AND section = ''"
            ) ?? -1
            
            #expect(total == 1)
            #expect(head == 1, "the surviving row must be the head row, not a section row")
        }
    }
    
    @Test("a meta-only projection stops the body from matching while the title still does")
    func metaOnlyProjectionDropsBodyTokensButKeepsMetadata() throws {
        // Given
        #expect(home.createNote(
            id: "meta-note",
            axis: "tech",
            title: "zephyrtitle",
            summary: "zephyrsummary",
            tags: ["tech"],
            content: "## A\nzephyrbody token\n"
        ).status == "ok")
        
        #expect(try matches("zephyrbody") > 0, "setup: the body should be indexed to begin with")
        
        // When
        try projectMetaOnly(id: "meta-note", title: "zephyrtitle", summary: "zephyrsummary")
        
        // Then
        #expect(try matches("zephyrbody") == 0, "the body kept matching after a meta-only projection")
        #expect(try matches("zephyrtitle") > 0, "the title must stay findable")
        #expect(try matches("zephyrsummary") > 0, "the summary must stay findable")
    }
    
    // MARK: - Private
    private func projectMetaOnly(id: String, title: String = "title", summary: String = "summary") throws {
        try home.database().write { database in
            try SetNoteFTSMetaOnlyTransaction(nid: id, title: title, summary: summary).perform(database)
        }
    }
    
    private func matches(_ token: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM notes_fts WHERE notes_fts MATCH ?",
                arguments: [token]
            ) ?? 0
        }
    }
}
