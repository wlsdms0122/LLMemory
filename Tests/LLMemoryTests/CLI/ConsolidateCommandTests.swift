//
//  ConsolidateCommandTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("ConsolidateCommand Tests", .serialized)
struct ConsolidateCommandTests {
    // MARK: - Property
    private let brain: CLIBrain
    
    // MARK: - Initializer
    init() throws {
        brain = try CLIBrain(prefix: "llmemory-cli-consolidate")
    }
    
    // MARK: - Test
    @Test("integrate runs against every table it joins")
    func integrateRunsClean() {
        // When
        let result = brain.run(["consolidate", "integrate", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(!result.standardError.contains("no such column"), "\(result.standardError)")
    }
    
    @Test("prune runs against every table it joins")
    func pruneRunsClean() {
        // When
        let result = brain.run(["consolidate", "prune", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(!result.standardError.contains("no such column"), "\(result.standardError)")
    }
    
    @Test("report runs against every table it joins")
    func reportRunsClean() {
        // When
        let result = brain.run(["consolidate", "report"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(!result.standardError.contains("no such column"), "\(result.standardError)")
    }
    
    @Test("the plain summary keeps 0/1 counters numeric instead of rendering them as booleans")
    func plainSummaryKeepsZeroOneNumeric() {
        // When
        let result = brain.run(["consolidate", "integrate"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(!result.standardOutput.contains("True"),
            "0/1 numeric summary fields rendered as booleans:\n\(result.standardOutput)")
        #expect(!result.standardOutput.contains("False"),
            "0/1 numeric summary fields rendered as booleans:\n\(result.standardOutput)")
        #expect(result.standardOutput.range(of: #"(?m)\s0$"#, options: .regularExpression) != nil,
            "expected a 0-valued numeric summary line:\n\(result.standardOutput)")
    }
    
    @Test("decay belongs to prune — integrate is non-destructive and may run often")
    func integrateDoesNotDecayButPruneDoes() {
        // Given
        brain.run(["query", "search", "PIIMaskingTransformer", "--json"])
        brain.run(["query", "search", "PIIMaskingTransformer", "--json"])
        
        // When
        let integrated = brain.run(["consolidate", "integrate", "--json"])
        let pruned = brain.run(["consolidate", "prune", "--json"])
        
        // Then
        #expect(integrated.succeeded, "\(integrated.standardError)")
        #expect(integrated.jsonObject()?["links_decayed"] as? Int == 0,
            "integrate must not decay links: \(integrated.standardOutput)")
        #expect(pruned.succeeded, "\(pruned.standardError)")
        #expect((pruned.jsonObject()?["links_decayed"] as? Int ?? 0) > 0,
            "prune must decay learned links: \(pruned.standardOutput)")
    }
    
    @Test("reference links are facts derived from the body — repeated prune must not erode them")
    func pruneKeepsReferenceLinks() {
        // Given
        brain.applyOps("""
            {"ops":[
              {"op":"create_note","id":"ref-dst","axis":"tech","title":"D","summary":"summary",\
            "tags":["tech"],"content":"## A\\nbody\\n"},
              {"op":"create_note","id":"ref-src","axis":"tech","title":"S","summary":"summary",\
            "tags":["tech"],"content":"## A\\nsee `ref-dst` here\\n"}
            ],"rationale":"test"}
            """)
        
        let before = referenceLinkCount()
        
        #expect(before > 0, "an explicit body reference should have produced a reference link")
        
        // When
        for _ in 0 ..< 15 { brain.run(["consolidate", "prune"]) }
        
        // Then
        #expect(referenceLinkCount() == before, "reference links must survive repeated prune")
    }
    
    // MARK: - Private
    private func referenceLinkCount() -> Int {
        let structure = brain.run(["query", "structure", "--json"])
        let links = structure.jsonObject()?["links"] as? [String: Any]
        let byKind = links?["by_kind"] as? [[String: Any]] ?? []
        
        return byKind.first { entry in entry["kind"] as? String == "reference" }?["count"] as? Int ?? 0
    }
}
