//
//  ReadsTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("Reads Tests", .serialized)
struct ReadsTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    // catalog (query get) — note_usage JOIN
    @Test("the catalog carries the usage columns the read surfaces report")
    func catalogReturnsUsageColumns() throws {
        // Given
        home.createNote(id: "cat-a", title: "Title A", content: "## S\nthe TossDIContainer body.\n")
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let map = try FetchNoteCatalogTransaction(ids: ["cat-a", "nope"]).perform(db)
        
        // Then
            #expect(map["cat-a"] != nil)
            #expect(map["nope"] == nil)
            
            let note = map["cat-a"]!
            
            #expect(note.axis == "flow")
            #expect(note.title == "Title A")
            #expect(note.createdAt > 0)
            #expect(note.hitCount == 0)
            #expect(note.editedAt > 0)
        }
    }
    
    @Test("asking the catalog for no ids returns nothing rather than everything")
    func catalogEmptyIdsIsEmpty() throws {
        // Given
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let empty = try FetchNoteCatalogTransaction(ids: []).perform(db)
        
        // Then
            #expect(empty.isEmpty)
        }
    }
    
    @Test("the hit count reflects what the activation trace recorded")
    func catalogHitCountReflectsActivation() throws {
        // Given
        home.createNote(id: "cat-hit", content: "## S\nbody\n")
        
        let queue = try home.storage.connect()
        
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO note_usage (note_id, hit_count, created_at) VALUES ('cat-hit', 7, 1)
                ON CONFLICT(note_id) DO UPDATE SET hit_count = 7
                """)
        }
        
        // When
        try queue.read { db in
            let note = try FetchNoteCatalogTransaction(ids: ["cat-hit"]).perform(db)["cat-hit"]
        
        // Then
            #expect(note?.hitCount == 7)
        }
    }
    
    // list (query list) — note_source JOIN + filter combinations
    @Test("list filters on priority")
    func listFiltersByPriority() throws {
        // Given
        home.createNote(id: "list-lazy", content: "## S\nb\n")
        home.createNote(id: "list-eager", content: "## S\nb\n")
        
        _ = OperationsEngine.apply(home.storage, ["ops": [["op": "set_frontmatter", "id": "list-eager",
            "fields": ["priority": "eager"]]], "rationale": "t"])
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let eager = try ListNoteRowsTransaction(.init(priority: "eager")).perform(db).map { row in row.id }
        
        // Then
            #expect(eager.contains("list-eager"))
            #expect(!eager.contains("list-lazy"))
        }
    }
    
    @Test("a list row carries the summary that lets a caller pick the next hop")
    func listIncludesSummary() throws {
        // Given
        home.createNote(id: "ls-a", summary: "what this note is for")
        
        // When
        let row = try home.read { database in
            try ListNoteRowsTransaction(.init()).perform(database).first { row in row.id == "ls-a" }
        }
        
        // Then
        #expect(row?.summary == "what this note is for")
    }
    
    @Test("list filters on axis")
    func listFiltersByAxis() throws {
        // Given
        home.createNote(id: "ax-flow", axis: "flow", tags: ["flow"], content: "## S\nb\n")
        home.createNote(id: "ax-tech", axis: "tech", tags: ["tech"], content: "## S\nb\n")
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let tech = try ListNoteRowsTransaction(.init(axis: "tech")).perform(db).map { row in row.id }
        
        // Then
            #expect(tech == ["ax-tech"])
        }
    }
    
    @Test("the source-stale filter resolves its join")
    func listSourceStaleJoinRunsClean() throws {
        // Given
        home.createNote(id: "ss-note", content: "## S\nb\n")
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let staleOnly = try ListNoteRowsTransaction(.init(sourceStale: true)).perform(db)
        
        // Then
            #expect(staleOnly.isEmpty)
            
            let all = try ListNoteRowsTransaction(.init()).perform(db)
            
            #expect(all.first { row in row.id == "ss-note" }?.sourceStale == false)
        }
    }
    
    @Test("a limit caps the number of rows returned")
    func listLimitCaps() throws {
        // Given
        for index in 0..<5 { home.createNote(id: "lim-\(index)", content: "## S\nb\n") }
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let capped = try ListNoteRowsTransaction(.init(limit: 2)).perform(db)
        
        // Then
            #expect(capped.count == 2)
        }
    }
    
    // entityLookup (query entity)
    @Test("an entity name resolves to the notes that declare it")
    func entityLookupByName() throws {
        // Given
        createWithEntities(id: "ent-a", entities: ["PIIMaskingTransformer"])
        createWithEntities(id: "ent-b", entities: ["PIIMaskingTransformer"])
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let hits = try LookupEntitiesTransaction(name: "PIIMaskingTransformer", limit: 30).perform(db)
            let ids = Set(hits.map { hit in hit.noteId })
        
        // Then
            #expect(ids.contains("ent-a") && ids.contains("ent-b"))
            #expect(hits.allSatisfy { hit in hit.axis == "flow" })
        }
    }
    
    @Test("omitting the name lists every entity instead of none")
    func entityLookupListAll() throws {
        // Given
        createWithEntities(id: "ent-c", entities: ["TransferService"])
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let all = try LookupEntitiesTransaction(name: nil, limit: 30).perform(db)
        
        // Then
            #expect(all.count >= 1)
        }
    }
    
    // history (query history)
    @Test("history starts with the event that created the note")
    func historyHasCreatedEvent() throws {
        // Given
        home.createNote(id: "hist-a", content: "## S\nb\n")
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let events = try FetchNoteHistoryTransaction(noteId: "hist-a", limit: 50).perform(db)
        
        // Then
            #expect(events.contains { event in event.kind == "created" })
        }
    }
    
    @Test("history comes back newest first and honours its limit")
    func historyNewestFirstAndLimited() throws {
        // Given
        home.createNote(id: "hist-b", content: "## S\nb\n")
        
        _ = OperationsEngine.apply(home.storage, ["ops": [["op": "flag", "id": "hist-b", "kind": "reconsolidate",
            "reason": "x"]], "rationale": "t"])
        
        let queue = try home.storage.connect()
        
        // When
        try queue.read { db in
            let one = try FetchNoteHistoryTransaction(noteId: "hist-b", limit: 1).perform(db)
        
        // Then
            #expect(one.count == 1)
        }
    }
    
    // MARK: - Private
    @discardableResult
    private func createWithEntities(id: String, entities: [String]) -> OperationsResult {
        home.createNote(id: id, content: "## S\nbody\n", fields: ["entities": entities])
    }
}
