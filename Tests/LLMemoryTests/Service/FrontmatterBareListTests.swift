//
//  FrontmatterBareListTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("FrontmatterBareList Tests", .serialized)
struct FrontmatterBareListTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    // Every list field is closed the same way, so each case below probes one field against that rule.
    @Test("a bare comma list is refused rather than split into a list of guesses")
    func bareTagsFailLoud() throws {
        // Then
        #expect(throws: FrontmatterError.malformedList(key: "tags", value: "alpha, beta")) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: alpha, beta"))
        }
    }
    
    @Test("the same rule holds for entities, not only for tags")
    func bareEntitiesFailLoud() throws {
        // Then
        #expect(throws: FrontmatterError.malformedList(key: "entities", value: "acct, xfer")) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: [a]\nentities: acct, xfer"))
        }
    }
    
    @Test("and for promoted_from — every list field is closed the same way")
    func barePromotedFromFailsLoud() throws {
        // Then
        #expect(throws: FrontmatterError.malformedList(key: "promoted_from", value: "old-note")) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: [a]\npromoted_from: old-note"))
        }
    }
    
    @Test("a quoted or braced value is refused instead of being split on commas")
    func quotedAndBracedValuesFailLoudInsteadOfSplitting() throws {
        // Then
        #expect(throws: FrontmatterError.self) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: \"a, b\""))
        }
        #expect(throws: FrontmatterError.self) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: {a, b}"))
        }
    }
    
    @Test("a bracketed list that does not close, or carries trailing junk, is refused")
    func malformedBracketListFailsLoud() throws {
        // Then
        #expect(throws: FrontmatterError.self) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: [unclosed"))
        }
        #expect(throws: FrontmatterError.self) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: [a] junk"))
        }
        #expect(throws: FrontmatterError.self) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: [a]\nentities: [broken"))
        }
    }
    
    @Test("the bracketed form is the one that parses, for every list field")
    func bracketedFormsParse() throws {
        // When
        let (document, _) = try Frontmatter.parse(Self.note(fields: "tags: [a, b]\nentities: [e1]\npromoted_from: [p1, p2]"))
        
        // Then
        #expect(document.tags == ["a", "b"])
        #expect(document.entities == ["e1"])
        #expect(document.promotedFrom == ["p1", "p2"])
    }
    
    @Test("a bracketed list survives a dump and reparse unchanged")
    func bracketedRoundTripIsStable() throws {
        // When
        let (original, _) = try Frontmatter.parse(Self.note(fields: "tags: [a, b]\nentities: [e1]"))
        let dumped = Frontmatter.dump(original)
        let (reparsed, _) = try Frontmatter.parse(dumped + "# body\n")
        
        // Then
        #expect(reparsed.tags == original.tags)
        #expect(reparsed.entities == original.entities)
    }
    
    @Test("an empty bracketed list is valid and means no items")
    func canonicalEmptyListIsValid() throws {
        // When
        let (document, _) = try Frontmatter.parse(Self.note(fields: "tags: []"))
        
        // Then
        #expect(document.tags == [])
    }
    
    @Test("one malformed duplicate poisons the key, whichever order the two appear in")
    func duplicateKeyBareLineFailsLoudDespiteBracketedSibling() throws {
        // Then
        #expect(throws: FrontmatterError.malformedList(key: "tags", value: "alpha, beta")) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: [a]\ntags: alpha, beta"))
        }
        #expect(throws: FrontmatterError.malformedList(key: "tags", value: "alpha, beta")) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: alpha, beta\ntags: [a]"))
        }
    }
    
    @Test("two well-formed duplicates resolve to the last one")
    func duplicateBracketedKeysKeepLastOccurrence() throws {
        // When
        let (document, _) = try Frontmatter.parse(Self.note(fields: "tags: [a]\ntags: [b]"))
        
        // Then
        #expect(document.tags == ["b"])
    }
    
    @Test("a YAML block list is refused — every line must be a single key: value")
    func blockStyleListFailsLoud() throws {
        // Then
        #expect(throws: FrontmatterError.malformedLine(line: "tags:")) {
            _ = try Frontmatter.parse(Self.note(fields: "tags:\n  - alpha\n  - beta"))
        }
        #expect(throws: FrontmatterError.malformedLine(line: "entities:")) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: [a]\nentities:"))
        }
    }
    
    @Test("a block scalar is refused for the same reason")
    func blockScalarFailsLoud() throws {
        // Then
        #expect(throws: FrontmatterError.malformedLine(line: "  first line")) {
            _ = try Frontmatter.parse("""
            ---
            id: fl-note
            title: t
            priority: lazy
            summary: |
              first line
            tags: [a]
            ---

            # body
            """)
        }
    }
    
    @Test("a line that is not a key: value pair at all is refused")
    func strayLineFailsLoud() throws {
        // Then
        #expect(throws: FrontmatterError.malformedLine(line: "- orphan item")) {
            _ = try Frontmatter.parse(Self.note(fields: "tags: [a]\n- orphan item"))
        }
    }
    
    @Test("what dump writes always parses back to exactly what it was given")
    func canonicalDumpPassesClosureRule() throws {
        // Given
        // No id: it is not a frontmatter field. The round trip is over what the
        // file actually carries, and the address is carried by the file itself.
        var document = FrontmatterDoc()
        
        document.title = "t"
        document.priority = "eager"
        document.summary = "s"
        document.tags = ["a", "b"]
        document.entities = ["e1"]
        document.promotedFrom = ["p1"]
        document.source = ["/abs/x.swift"]
        document.template = "tpl"
        document.locked = true
        document.stale = true
        document.invalidatedAt = 5
        document.invalidatedReason = "r"
        document.extra["custom"] = "v"
        
        // When
        let (reparsed, _) = try Frontmatter.parse(Frontmatter.dump(document) + "# body\n")
        
        // Then
        #expect(reparsed == document)
    }
    
    // MARK: - Private
    private static func note(fields: String) -> String {
        """
        ---
        id: fl-note
        title: t
        priority: lazy
        summary: s
        \(fields)
        ---

        # body
        """
    }
}
