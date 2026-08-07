//
//  FrontmatterTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import LLMemory

@Suite("Frontmatter Tests")
struct FrontmatterTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("parse and dump are idempotent — repeated rewrites do not accumulate blank lines")
    func roundTripDoesNotAccumulateBlankLines() throws {
        // Given
        var document = FrontmatterDoc(
            id: "rt-1", title: "t", axis: "tech",
            priority: "lazy", summary: "s", tags: ["tech"]
        )
        
        let body = "# Heading\n\ncontent line\n"
        let initial = Frontmatter.dump(document) + body
        
        var current = initial
        
        for _ in 0..<5 {
            let (parsedDocument, parsedBody) = try Frontmatter.parse(current)
        
        // When
            document = parsedDocument
            current = Frontmatter.dump(document) + parsedBody
        }
        
        // Then
        #expect(current == initial, "round-trip should be idempotent")
    }
    
    @Test("extra blank lines after the frontmatter heal on the next rewrite")
    func multipleBlanksHealOnRewrite() throws {
        // Given
        let document = FrontmatterDoc(
            id: "heal-1", title: "t", axis: "tech",
            priority: "lazy", summary: "s", tags: ["tech"]
        )
        
        // When
        let polluted = Frontmatter.dump(document).replacingOccurrences(of: "---\n\n", with: "---\n\n\n\n") + "# Body\n"
        
        // Then
        #expect(polluted.contains("---\n\n\n\n"))
        
        let (parsed, body) = try Frontmatter.parse(polluted)
        let healed = Frontmatter.dump(parsed) + body
        
        #expect(!healed.contains("---\n\n\n"), "healed should have at most 1 blank line after ---")
        #expect(healed.contains("---\n\n# Body"))
    }
    
    @Test("a missing blank line after the frontmatter heals too — both directions converge")
    func noBlankAlsoHealsToCanonical() throws {
        // Given
        let document = FrontmatterDoc(
            id: "heal-2", title: "t", axis: "tech",
            priority: "lazy", summary: "s", tags: ["tech"]
        )
        
        // When
        let raw = Frontmatter.dump(document).replacingOccurrences(of: "---\n\n", with: "---\n") + "# Body\n"
        let (parsed, body) = try Frontmatter.parse(raw)
        let healed = Frontmatter.dump(parsed) + body
        
        // Then
        #expect(healed.contains("---\n\n# Body"))
    }
    
    @Test("a field this binary does not know survives a rewrite instead of being dropped")
    func unknownFieldsSurviveDump() throws {
        // Given
        let file = """
        ---
        id: x-1
        title: t
        axis: tech
        priority: lazy
        tags: [tech]
        summary: s
        custom_axis_score: 0.87
        owner: jineun
        ---

        # Body
        """
        
        // When
        let (document, _) = try Frontmatter.parse(file)
        
        // Then
        #expect(document.extra["custom_axis_score"] == "0.87")
        #expect(document.extra["owner"] == "jineun")
        
        let dumped = Frontmatter.dump(document)
        
        #expect(dumped.contains("custom_axis_score: 0.87"), "dump dropped an unknown field → silent loss on rewrite")
        #expect(dumped.contains("owner: jineun"))
        
        let (reparsed, _) = try Frontmatter.parse(dumped + "# Body\n")
        
        #expect(reparsed.extra == document.extra)
    }
}
