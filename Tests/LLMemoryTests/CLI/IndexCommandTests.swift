//
//  IndexCommandTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("IndexCommand Tests", .serialized)
struct IndexCommandTests {
    // MARK: - Property
    private let brain: CLIBrain
    
    // MARK: - Initializer
    init() throws {
        brain = try CLIBrain(prefix: "llmemory-cli-index")
    }
    
    // MARK: - Test
    @Test("an incremental build leaves the corpus searchable")
    func buildIncremental() {
        // When
        let result = brain.run(["index", "build", "--json"])
        
        // Then
        let searched = brain.run(["query", "search", "PIIMaskingTransformer", "--json"])
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(searched.ids().contains("log-masking"))
    }
    
    @Test("--rebuild re-derives the index and the vectors from cortex")
    func rebuildRederivesIndexAndVectors() {
        // When
        let result = brain.run(["index", "build", "--rebuild"])
        
        // Then
        let searched = brain.run(["query", "search", "PIIMaskingTransformer", "--json"])
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(searched.ids().contains("log-masking"))
    }
    
    @Test("verify integrity at the deepest level reports a clean freshly-built brain")
    func verifyIntegrityAtLevelTwo() {
        // When
        let result = brain.run(["index", "verify", "integrity", "--level", "2"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
    }
    
    @Test("verify sources runs against the note_source join")
    func verifySources() {
        // When
        let result = brain.run(["index", "verify", "sources", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(!result.standardError.contains("no such column"), "\(result.standardError)")
    }
    
    @Test("verify terms runs against the retrieval-term tables")
    func verifyTerms() {
        // When
        let result = brain.run(["index", "verify", "terms", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(!result.standardError.contains("no such column"), "\(result.standardError)")
    }
    
    @Test("vector decomposes the link graph without error")
    func vectorBuilds() {
        // When
        let result = brain.run(["index", "vector", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
    }
}
