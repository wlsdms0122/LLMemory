//
//  FieldMergeGateInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// set_frontmatter reports what it wrote. A value it cannot map has to be refused — reporting it as
// applied tells the caller a change landed when nothing did.
@Suite("FieldMergeGateInvariant Tests", .serialized)
struct FieldMergeGateInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    // Each field is declared with a type; each case here hands it the wrong one.
    @Test("a wrongly typed field is refused rather than dropped and reported as applied",
        arguments: ["title", "summary", "priority", "tags"])
    func aFieldThatCannotBeMappedIsRejected(field: String) throws {
        // Given
        home.createNote(id: "mf-note", title: "original")
        
        // When
        let result = home.apply([
            "op": "set_frontmatter", "id": "mf-note", "fields": [field: Self.wronglyTypedValue(for: field)]
        ])
        
        // Then
        #expect(result.status != "ok", "\(field) was dropped and reported as applied")
        #expect(try title(of: "mf-note") == "original")
    }
    
    @Test("dry-run refuses the same shape apply refuses — the two must not disagree")
    func dryRunRefusesTheSameShape() {
        // Given
        home.createNote(id: "mf-dry")
        
        // When
        let result = OperationsEngine.dryRun(home.storage, home.brain, [
            "ops": [["op": "set_frontmatter", "id": "mf-dry", "fields": ["title": 123]]],
            "rationale": "test"
        ])
        
        // Then
        #expect(result.status != "ok", "dry-run accepted what apply rejects")
    }
    
    @Test("a well-typed field still applies — the gate rejects on type, not on the op")
    func wellTypedFieldsStillApply() throws {
        // Given
        home.createNote(id: "mf-ok", title: "original")
        
        // When
        let result = home.apply([
            "op": "set_frontmatter", "id": "mf-ok", "fields": ["title": "new", "summary": "s2"]
        ])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try title(of: "mf-ok") == "new")
    }
    
    @Test("a note may drop the tag that shares its axis name — the drawer does not dictate the label")
    func droppingTheAxisTagIsAllowed() {
        // Given
        home.createNote(id: "ax-note", tags: ["flow", "x"])
        
        let dropsAxisTag: [String: Any] = [
            "ops": [["op": "set_frontmatter", "id": "ax-note", "fields": ["tags": ["x", "y"]]]],
            "rationale": "test"
        ]
        
        // Then
        #expect(OperationsEngine.dryRun(home.storage, home.brain, dropsAxisTag).status == "ok")
        #expect(OperationsEngine.apply(home.storage, home.brain, dropsAxisTag).status == "ok")
    }
    
    @Test("an unknown field is kept as a custom frontmatter field rather than refused")
    func unknownFieldBecomesACustomField() throws {
        // Given
        home.createNote(id: "mf-extra", tags: ["flow"])
        
        // When
        let result = home.apply([
            "op": "set_frontmatter", "id": "mf-extra", "fields": ["affect": "high"]
        ])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try home.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT value FROM note_extra WHERE note_id = ? AND key = ?",
                arguments: ["mf-extra", "affect"]
            )
        } == "high")
    }
    
    @Test("a field with its own op stays refused — set_frontmatter is not a back door to identity")
    func reservedFieldStaysRefused() {
        // Given
        home.createNote(id: "mf-reserved", tags: ["flow"])
        
        // Then
        #expect(home.apply([
            "op": "set_frontmatter", "id": "mf-reserved", "fields": ["template": "some-template"]
        ]).status != "ok")
    }
    
    // MARK: - Private
    private static func wronglyTypedValue(for field: String) -> Any {
        switch field {
        case "title": 123
        case "summary": ["a"]
        case "priority": 1
        default: "flow"
        }
    }
    
    private func title(of noteId: String) throws -> String? {
        try home.read { database in
            try String.fetchOne(database, sql: "SELECT title FROM notes WHERE id = ?", arguments: [noteId])
        }
    }
}
