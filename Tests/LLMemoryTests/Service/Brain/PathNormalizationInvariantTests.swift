//
//  PathNormalizationInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("PathNormalizationInvariant Tests", .serialized)
struct PathNormalizationInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("relative() answers from the path alone — a note that does not exist yet still has one")
    func relativeIsExistenceIndependent() {
        // Given
        let root = home.layout.brainRoot
        
        // Then
        #expect(home.layout.relative(of: root.appendingPathComponent("cortex")) == "cortex")
        #expect(home.layout.relative(of: root.appendingPathComponent("cortex/absent.md"))
            == "cortex/absent.md")
        #expect(home.layout.relative(of: home.url.appendingPathComponent("cortex/absent.md"))
            == "cortex/absent.md")
        #expect(home.layout.relative(of: URL(fileURLWithPath: "/etc/passwd")) == nil,
            "a path outside the brain has no relative form")
    }
    
    // /tmp is a symlink to /private/tmp on macOS, so a home given as one and resolved as the other is
    // the concrete case where an unnormalized path stops matching itself.
    @Test("a home under /private/tmp indexes its seeds — symlinked roots resolve to one form")
    func initUnderPrivateTmpIndexesSeeds() {
        // Given
        let root = URL(fileURLWithPath: "/private/tmp/llmemory-pathinit-\(UUID().uuidString)")
        
        defer { try? FileManager.default.removeItem(at: root) }
        
        // When
        let result = CLIRunner().run(["init", "--json", "--home", root.path])
        
        // Then
        let errors = result.jsonObject()?["errors"] as? [String] ?? []
        let indexed = result.jsonObject()?["indexed"] as? Int ?? 0
        
        #expect(result.succeeded, "init under /private/tmp failed: \(result.standardError)")
        #expect(errors.isEmpty, "init reported errors: \(errors)")
        #expect(indexed >= Seed.notes.count, "seeded notes were not indexed (indexed=\(indexed))")
    }
}
