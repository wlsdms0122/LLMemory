//
//  GuideTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("Guide Tests")
struct GuideTests {
    // MARK: - Property
    private let source = PackageSource()
    
    // MARK: - Initializer
    // MARK: - Test
    @Test("the embedded guide is byte-identical to the document it was generated from")
    func embeddedGuideMatchesDocumentFile() throws {
        // When
        let document = try String(contentsOf: source.file("document/embed/GUIDE.md"), encoding: .utf8)
        
        // Then
        #expect(document == Guide.markdown,
            "document/embed/GUIDE.md and Guide.swift diverged — run tool/set-up.sh")
    }
    
    @Test("init leaves the guide in the state root as its README")
    func initWritesGuideAsStateReadme() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-guide-init")
        
        // When
        let readme = brain.file("README.md")
        
        // Then
        #expect(try String(contentsOf: readme, encoding: .utf8) == Guide.markdown)
    }
    
    @Test("re-running init refreshes a stale README — the manual outside the brain follows the binary")
    func reinitRefreshesStateReadme() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-guide-reinit")
        let readme = brain.file("README.md")
        
        try "stale edit".write(to: readme, atomically: true, encoding: .utf8)
        
        // When
        let result = brain.run(["init"])
        
        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(try String(contentsOf: readme, encoding: .utf8) == Guide.markdown)
    }
}
