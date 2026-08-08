//
//  EpisodicTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// A note's lifecycle is recorded as events rather than inferred from its current row, so what happened
// to it stays answerable after the fact.
@Suite("Episodic Tests", .serialized)
struct EpisodicTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("creating a note records that it was created")
    func createRecordsEvent() throws {
        // When
        #expect(create("lc-test-1").status == "ok")
        
        // Then
        #expect(try lifecycleKinds(of: "lc-test-1") == ["created"])
    }
    
    @Test("revalidating clears the stale flag and records the whole sequence that led there")
    func revalidateClearsStaleAndRecordsEvent() throws {
        // Given
        create("lc-reval")
        
        home.apply(["op": "invalidate", "id": "lc-reval", "reason": "old"])
        
        // When
        let result = home.apply(["op": "revalidate", "id": "lc-reval", "reason": "content fresh now"])
        
        // Then
        let stale = try home.read { database in
            try Int.fetchOne(database, sql: "SELECT stale FROM notes WHERE id = 'lc-reval'") ?? -1
        }
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(stale == 0)
        #expect(try lifecycleKinds(of: "lc-reval") == ["created", "invalidated", "revalidated"])
    }
    
    @Test("editing a section records an edit that names the op responsible")
    func patchSectionRecordsEditedEvent() throws {
        // Given
        create("lc-edit", content: "## A\nbody\n")
        
        // When
        home.apply([
            "op": "patch_section", "id": "lc-edit", "section": "## A",
            "action": "replace", "content": "new body\n"
        ])
        
        // Then
        let events = try home.read { database -> [(kind: String, reason: String?)] in
            try Row.fetchAll(database, sql: """
                SELECT kind, reason FROM note_lifecycle_events WHERE note_id = 'lc-edit' ORDER BY id
                """).map { row in (row["kind"] as String, row["reason"] as String?) }
        }
        
        #expect(events[0].kind == "created")
        #expect(events[0].reason == nil)
        #expect(events[1].kind == "edited")
        #expect((events[1].reason ?? "").contains("patch_section"), "the event must name what edited it")
    }
    
    @Test("editing the frontmatter is an edit too, not a silent change")
    func setFrontmatterRecordsEditedEvent() throws {
        // Given
        create("lc-fm")
        
        // When
        home.apply(["op": "set_frontmatter", "id": "lc-fm", "fields": ["summary": "s2"]])
        
        // Then
        #expect(try lifecycleKinds(of: "lc-fm") == ["created", "edited"])
    }
    
    @Test("revalidating a note that is not stale is refused rather than recorded as a no-op")
    func revalidateRejectsNonStale() {
        // Given
        create("lc-reval2")
        
        // When
        let result = home.apply(["op": "revalidate", "id": "lc-reval2", "reason": "n/a"])
        
        // Then
        #expect(result.status == "rejected")
        #expect(result.error.contains("not stale"))
    }
    
    @Test("the schema carries no leftover from the episodic-notes design", arguments: [
        "episodic_notes", "axis_centroids", "tag_cooccur", "event_daily"
    ])
    func retiredTablesAreGone(table: String) throws {
        #expect(try !tableExists(table), "\(table) is a retired table and must not exist")
    }
    
    @Test("note_meta is the table that replaced them, and it is present")
    func noteMetaTablePresent() throws {
        #expect(try tableExists("note_meta"))
    }
    
    @Test("an axis has no kind column — an axis is not typed")
    func axesHasNoKindColumn() throws {
        // When
        let columns = try home.read { database in
            Set(try Row.fetchAll(database, sql: "PRAGMA table_info(axes)").map { row in row["name"] as String })
        }
        
        // Then
        #expect(!columns.contains("kind"))
    }
    
    // MARK: - Private
    @discardableResult
    private func create(_ noteId: String, content: String = "b") -> OpsTransaction.Result {
        home.createNote(id: noteId, axis: "tech", title: "x", tags: ["tech", "test"], content: content)
    }
    
    private func lifecycleKinds(of noteId: String) throws -> [String] {
        try home.read { database in
            try String.fetchAll(database, sql: """
                SELECT kind FROM note_lifecycle_events WHERE note_id = ? ORDER BY id
                """, arguments: [noteId])
        }
    }
    
    private func tableExists(_ name: String) throws -> Bool {
        try home.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
                arguments: [name]
            ) != nil
        }
    }
}
