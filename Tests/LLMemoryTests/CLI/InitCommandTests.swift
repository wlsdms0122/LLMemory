//
//  InitCommandTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation

@Suite("InitCommand Tests", .serialized)
struct InitCommandTests {
    // MARK: - Property
    private let brain: CLIBrain
    
    // MARK: - Initializer
    init() throws {
        brain = try CLIBrain(prefix: "llmemory-cli-init")
    }
    
    // MARK: - Test
    @Test("init on an already-initialized home says so instead of re-seeding it")
    func initIsIdempotent() {
        // When
        let result = brain.run(["init", "--json"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(result.jsonObject()?["already_initialized"] as? Bool == true)
    }
}
