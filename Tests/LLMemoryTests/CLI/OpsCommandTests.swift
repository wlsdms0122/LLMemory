//
//  OpsCommandTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("OperationsCommand Tests", .serialized)
struct OpsCommandTests {
    // MARK: - Property
    private let brain: CLIBrain
    
    // MARK: - Initializer
    init() throws {
        brain = try CLIBrain(prefix: "llmemory-cli-ops")
    }
    
    // MARK: - Test
    @Test("dry-run validates the transaction and writes nothing")
    func dryRunValidatesWithoutPersisting() {
        // When
        let result = brain.run(["operations", "dry-run", "--json", "--input", """
            {"ops":[{"op":"create_note","id":"dry-x","axis":"tech","title":"title","summary":"summary",\
            "tags":["tech"],"content":"## A\\nbody\\n"}],"rationale":"test"}
            """])
        
        // Then
        let fetched = brain.run(["query", "get", "dry-x", "--json"])
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(fetched.exitCode != 0, "dry-run must not persist the note")
    }
    
    @Test("delete moves the note file into .trash and takes it out of query range")
    func deleteMovesNoteToTrash() {
        // When
        let deleted = brain.applyOps("""
            {"ops":[{"op":"delete_note","id":"transfer-flow","reason":"test"}],"rationale":"test"}
            """)
        
        // Then
        let trashed = FileManager.default.enumerator(atPath: brain.path + "/cortex/.trash")?
            .compactMap { element in element as? String } ?? []
        let fetched = brain.run(["query", "get", "transfer-flow", "--json"])
        
        #expect(deleted.succeeded, "\(deleted.standardError)")
        #expect(trashed.contains { path in path.hasSuffix("transfer-flow.md") }, "\(trashed)")
        #expect(fetched.exitCode != 0)
    }
    
    @Test("restore brings a trashed note back into query range")
    func restoreBringsNoteBack() {
        // Given
        let deleted = brain.applyOps("""
            {"ops":[{"op":"delete_note","id":"persona-tone","reason":"test"}],"rationale":"test"}
            """)
        
        #expect(deleted.succeeded, "\(deleted.standardError)")
        
        // When
        let restored = brain.applyOps("""
            {"ops":[{"op":"restore","id":"persona-tone"}],"rationale":"test"}
            """)
        
        // Then
        let fetched = brain.run(["query", "get", "persona-tone", "--json"])
        
        #expect(restored.succeeded, "\(restored.standardError)")
        #expect(fetched.succeeded, "restored note should be gettable: \(fetched.standardError)")
    }
}
