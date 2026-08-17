//
//  OpsRequiredEnforcementTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// An op's schema is the single declaration of what it requires. Dispatch reads it, so a field that
// is required in the schema is refused without any handler restating the rule.
@Suite("OpsRequiredEnforcement Tests", .serialized)
struct OpsRequiredEnforcementTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a missing required field is refused by the schema, and the field is named")
    func missingRequiredFieldRejectedFromSchema() {
        // Given
        home.createNote(id: "req-note")
        
        // When
        let result = home.apply(["op": "delete_note", "id": "req-note"])
        
        // Then
        #expect(result.status != "ok")
        #expect(result.error.contains("reason"), "the schema declaration is the gate — got \(result.error)")
    }
    
    @Test("a conditionally required field is refused too, and the condition lives in the schema")
    func requiredUnlessWaiverIsSchemaDriven() throws {
        // When
        let result = home.apply([
            "op": "create_note", "id": "no-content", "axis": "flow",
            "title": "title", "summary": "summary", "tags": ["flow"]
        ])
        
        // Then
        let field = try schema(of: "create_note").fields.first { field in field.name == "content" }
        
        #expect(result.status != "ok")
        #expect(result.error.contains("content"))
        #expect(field?.requiredUnless == "template", "the waiver must be declared, not hand-rolled")
    }
    
    @Test("every id- or axis-shaped field declares its role, so db extraction can see it")
    func fieldRoleIsDeclared() {
        // When
        let violations = home.operationsEngine.registry.handlers.flatMap { opName, handler in
            handler.schema.fields
                .filter { field in field.role == .plain && Self.carriesScope(field.name) }
                .map { field in "\(opName).\(field.name)" }
        }
        
        // Then
        #expect(violations.isEmpty, """
            an id/axis-shaped field with no declared role is a blind spot for targetIds: \(violations.sorted().joined(separator: ", "))
            """)
    }
    
    @Test("derived db covers where an op sends things, not only where it reads them")
    func derivedScopeCoversDestinations() throws {
        // Given
        let relocate = try schema(of: "relocate_section")
        let split = try schema(of: "split_note")
        
        // When
        let relocateIds = relocate.mentionedNoteIds(in: ["from_id": "a", "to_id": "b", "section": "## s"])
        let splitIds = split.mentionedNoteIds(in: [
            "from_id": "a",
            "into": [["id": "c1", "axis": "tech"]]
        ])
        
        // Then
        #expect(relocateIds == ["a", "b"], "the destination must be in db — got \(relocateIds)")
        #expect(splitIds == ["a", "c1"])
    }
    
    // MARK: - Private
    private static func carriesScope(_ name: String) -> Bool {
        let identifiers = ["id", "ids", "src", "dst"]
        let isIdShaped = identifiers.contains(name) || name.hasSuffix("_id") || name.hasSuffix("_ids")
        let isSpecShaped = name == "into"
        
        return isIdShaped || isSpecShaped
    }
    
    private func schema(of op: String) throws -> OperationSchema {
        guard let handler = home.operationsEngine.registry[op] else { throw TestFailure("no handler registered for \(op)") }
        
        return handler.schema
    }
}
