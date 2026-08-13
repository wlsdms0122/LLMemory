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
        #expect(searched.ids().contains("tech.log-masking"))
    }
    
    @Test("--rebuild re-derives the index and the vectors from cortex")
    func rebuildRederivesIndexAndVectors() {
        // When
        let result = brain.run(["index", "build", "--rebuild"])
        
        // Then
        let searched = brain.run(["query", "search", "PIIMaskingTransformer", "--json"])
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(searched.ids().contains("tech.log-masking"))
    }
    
    // The user-facing contract of "reindex reports failure": the real binary
    // partitions successes from failures, writes failures to stderr, and
    // exits 1 — the whole storage.run + exit-code path in one shot.
    @Test("--path reindex partitions success from failure and exits 1")
    func reindexReportsFailureThroughTheRealBinary() {
        // Given — --path resolves relative arguments against the CWD, so the
        // subprocess needs absolute paths into the fixture home.
        let existing = brain.noteURL(id: "tech.di-container").path
        let missing = brain.file("cortex/missing.md").path

        // When
        let clean = brain.run(["index", "build", "--path", existing, "--json"])
        let mixed = brain.run(["index", "build", "--path", existing, missing, "--json"])

        // Then
        #expect(clean.succeeded, "\(clean.standardError)")
        #expect(clean.standardOutput.contains("\"return_code\""), "\(clean.standardOutput)")

        #expect(mixed.exitCode == 1, "a failed path did not flip the exit code")
        #expect(mixed.standardError.contains("missing.md"), "\(mixed.standardError)")
        #expect(mixed.standardOutput.contains("tech.di-container"), "the successful path vanished from the output")
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
