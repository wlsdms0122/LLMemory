//
//  CandidatesCommandTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("CandidatesCommand Tests", .serialized)
struct CandidatesCommandTests {
    // MARK: - Property
    private let brain: CLIBrain
    
    // MARK: - Initializer
    init() throws {
        brain = try CLIBrain(prefix: "llmemory-cli-candidates")
    }
    
    // MARK: - Test
    // Every kind joins a different set of tables. Running them one by one keeps a broken join from
    // hiding behind a kind that happens to be queried first.
    @Test("every candidate kind resolves its joins", arguments: [
        "split", "reconsolidate", "enrich_review", "clusters", "missing_edge", "near_duplicate", "all"
    ])
    func candidateKindRunsClean(kind: String) {
        // When
        let result = brain.run(["consolidate", "candidates", "--kind", kind, "--json"])
        
        // Then
        #expect(result.succeeded, "candidates \(kind): \(result.standardError)")
        #expect(!result.standardError.contains("no such column"), "candidates \(kind): \(result.standardError)")
    }
    
    @Test("reconsolidate surfaces the note the seed flagged")
    func reconsolidateSurfacesFlagged() {
        // When
        let result = brain.run(["consolidate", "candidates", "--kind", "reconsolidate", "--json"])
        
        // Then
        let ids = Set((result.jsonArray() ?? []).compactMap { row in
            row["id"] as? String ?? row["note_id"] as? String
        })
        
        #expect(result.succeeded, "\(result.standardError)")
        #expect(ids.contains("tech.log-masking"))
    }
    
    @Test("--kind is required — a missing kind is refused, not silently defaulted")
    func missingKindIsRefused() {
        // When
        let result = brain.run(["consolidate", "candidates"])
        
        // Then
        #expect(result.exitCode != 0)
    }
}
