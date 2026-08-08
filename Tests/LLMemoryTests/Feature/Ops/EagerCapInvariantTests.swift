//
//  EagerCapInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Eager notes load on every boot, so their number is capped. The cap has to hold whichever door a
// promotion comes through, and it must never wedge a corpus that is already over it.
@Suite("EagerCapInvariant Tests", .serialized)
struct EagerCapInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    private let cap: Int
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        cap = Config.getInt("eager.max_count", default: 20)
    }
    
    // MARK: - Test
    @Test("a single batch that would breach the cap is rejected whole, leaving nothing behind")
    func batchOfEagerCreatesCannotBreachCap() throws {
        // When
        let result = home.apply((0 ..< cap + 5).map { index in eagerNote("cap-\(index)") })
        
        // Then
        #expect(result.status == "failed", "a batch past the cap must be refused — got \(result.status)")
        #expect(result.error.contains("eager cap"), "the reason must reach the caller — got \(result.error)")
        #expect(try eagerCount() == 0, "rolled back — no partial application")
    }
    
    @Test("promoting through set_frontmatter meets the same cap as creating an eager note")
    func setFrontmatterPriorityIsGatedToo() throws {
        // Given
        #expect(home.apply((0 ..< cap).map { index in eagerNote("cap-\(index)") }).status == "ok")
        
        home.createNote(id: "cap-extra")
        
        // When
        let result = home.apply([
            "op": "set_frontmatter", "id": "cap-extra", "fields": ["priority": "eager"]
        ])
        
        // Then
        #expect(result.status == "failed",
            "promotion must meet the same invariant — got \(result.status) \(result.error)")
        #expect(try eagerCount() == cap)
    }
    
    @Test("a corpus already over the cap stays writable — creating lazily and demoting still work")
    func overCapCorpusStaysWritable() throws {
        // Given — pushed over the cap behind the gate's back, the way a hand-edited brain would be.
        #expect(home.apply((0 ..< cap).map { index in eagerNote("cap-\(index)") }).status == "ok")
        
        try home.storage.writeLock {
            try home.database().write { database in
                try database.execute(sql: "UPDATE notes SET priority = 'eager'")
            }
        }
        
        // When
        let created = home.apply([eagerNote("cap-lazy", priority: "lazy")])
        let demoted = home.apply([
            "op": "set_frontmatter", "id": "cap-0", "fields": ["priority": "lazy"]
        ])
        
        // Then
        #expect(created.status == "ok", "an over-cap corpus must still accept a lazy note")
        #expect(demoted.status == "ok", "demotion must always be available — got \(demoted.error)")
    }
    
    // MARK: - Private
    private func eagerNote(_ id: String, priority: String = "eager") -> [String: Any] {
        [
            "op": "create_note", "id": id, "axis": "flow", "title": "title",
            "tags": ["flow"], "summary": "summary", "content": "## A\nbody\n", "priority": priority
        ]
    }
    
    private func eagerCount() throws -> Int {
        try home.read { database in try Notes.eagerCount(database) }
    }
}
