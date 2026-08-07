//
//  FrontmatterSourceTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory
@Suite("FrontmatterSource Tests", .serialized)
struct FrontmatterSourceTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("a single source may be written bare, without brackets")
    func bareStringSourceIsParsed() throws {
        // When
        let (document, _) = try Frontmatter.parse(Self.note("/abs/kernel/x.swift"))
        
        // Then
        #expect(document.source == ["/abs/kernel/x.swift"], "bare-string source must be honored, not dropped — got \(document.source as Any)")
    }
    
    @Test("the bracketed list form still parses")
    func bracketedSourceStillParsed() throws {
        // When
        let (document, _) = try Frontmatter.parse(Self.note("[\"/abs/a.swift\", \"/abs/b.swift\"]"))
        
        // Then
        #expect(document.source == ["/abs/a.swift", "/abs/b.swift"], "bracketed list must still parse — got \(document.source as Any)")
    }
    
    @Test("a bare source survives a dump and reparse")
    func bareSourceSurvivesRoundTrip() throws {
        // When
        let (original, _) = try Frontmatter.parse(Self.note("/abs/only.swift"))
        let dumped = Frontmatter.dump(original)
        let (reparsed, _) = try Frontmatter.parse(dumped + "\n# body\n")
        
        // Then
        #expect(reparsed.source == ["/abs/only.swift"], "bare source lost across round-trip — got \(reparsed.source as Any)")
    }
    
    @Test("a duplicated key resolves to the last occurrence, like every other field")
    func duplicateSourceKeepsLastOccurrence() throws {
        // When
        let (document, _) = try Frontmatter.parse(Self.note("[\"/abs/first.swift\"]\nsource: [\"/abs/second.swift\"]"))
        
        // Then
        #expect(document.source == ["/abs/second.swift"], "duplicate source must keep the last occurrence — got \(document.source as Any)")
    }
    
    @Test("that holds whichever of the two forms comes last")
    func duplicateSourceMixedFormsKeepLastOccurrence() throws {
        // When
        let (bareLast, _) = try Frontmatter.parse(Self.note("[\"/abs/first.swift\"]\nsource: /abs/second.swift"))
        
        // Then
        #expect(bareLast.source == ["/abs/second.swift"], "bare last occurrence lost to a bracketed sibling — got \(bareLast.source as Any)")
        
        let bracketLast = try Frontmatter.parse(Self.note("/abs/first.swift\nsource: [\"/abs/second.swift\"]")).0
        
        #expect(bracketLast.source == ["/abs/second.swift"], "bracketed last occurrence lost — got \(bracketLast.source as Any)")
    }
    
    @Test("a bracketed value that is not valid JSON is refused rather than guessed at")
    func bracketedNonJSONFailsLoud() throws {
        // Then
        #expect(throws: FrontmatterError.malformedSource(value: "[/abs/a.swift]")) {
            _ = try Frontmatter.parse(Self.note("[/abs/a.swift]"))
        }
        #expect(throws: FrontmatterError.self) {
            _ = try Frontmatter.parse(Self.note("[\"/abs/a.swift\""))
        }
        #expect(throws: FrontmatterError.self) {
            _ = try Frontmatter.parse(Self.note("[\"/abs/a.swift\", /abs/b.swift]"))
        }
    }
    
    @Test("a leading bracket always means the list form — quoting is how to write one literally")
    func bracketIsReservedForTheListFormAndQuotingIsTheEscapeHatch() throws {
        // Then
        #expect(throws: FrontmatterError.malformedSource(value: "[RFC-123]")) {
            _ = try Frontmatter.parse(Self.note("[RFC-123]"))
        }
        
        let (document, _) = try Frontmatter.parse(Self.note("[\"[RFC-123]\"]"))
        
        #expect(document.source == ["[RFC-123]"])
    }
    
    @Test("one malformed duplicate poisons the key, whichever side it is on")
    func bracketedNonJSONFailsLoudDespiteWellFormedSibling() throws {
        // Then
        #expect(throws: FrontmatterError.malformedSource(value: "[/abs/bad.swift]")) {
            _ = try Frontmatter.parse(Self.note("[\"/abs/ok.swift\"]\nsource: [/abs/bad.swift]"))
        }
        #expect(throws: FrontmatterError.malformedSource(value: "[/abs/bad.swift]")) {
            _ = try Frontmatter.parse(Self.note("[/abs/bad.swift]\nsource: [\"/abs/ok.swift\"]"))
        }
    }
    
    @Test("an element that cannot become a path is refused, not normalized away")
    func jsonArrayWithUnmappableElementsFailsLoud() throws {
        // Then
        for bad in ["[123]", "[null]", "[\"\"]", "[{\"foo\": \"bar\"}]", "[[\"/abs/a.swift\"]]",
            "[\"/abs/a.swift\", 123]", "[{\"path\": \"\"}]"] {
            #expect(throws: FrontmatterError.self, "unmappable element must fail loud, not normalize away: \(bad)") {
                _ = try Frontmatter.parse(Self.note(bad))
            }
        }
    }
    
    @Test("trailing text after the list is refused")
    func bracketedNonArrayJSONFailsLoud() throws {
        // Then
        #expect(throws: FrontmatterError.self) {
            _ = try Frontmatter.parse(Self.note("[\"/abs/a.swift\"] extra"))
        }
    }
    
    @Test("an object element collapses to its path")
    func jsonDictEntriesCollapseToTheirPath() throws {
        // When
        let (document, _) = try Frontmatter.parse(Self.note("[{\"path\": \"/abs/a.swift\"}, \"/abs/b.swift\"]"))
        
        // Then
        #expect(document.source == ["/abs/a.swift", "/abs/b.swift"])
    }
    
    @Test("every accepted spelling canonicalizes without losing what it meant")
    func acceptedNonCanonicalInputCanonicalizesWithoutLoss() throws {
        // When
        for (input, expected) in [("/abs/a.swift", ["/abs/a.swift"]),
            ("[{\"path\": \"/abs/a.swift\"}]", ["/abs/a.swift"]),
            ("[]", [])] {
            let (parsed, _) = try Frontmatter.parse(Self.note(input))
        
        // Then
            #expect(parsed.source == expected, "\(input) normalized to \(parsed.source as Any)")
            
            let (reparsed, _) = try Frontmatter.parse(Frontmatter.dump(parsed) + "# body\n")
            
            #expect(reparsed.source ?? [] == parsed.source ?? [],
                "\(input) lost meaning across dump → parse — got \(reparsed.source as Any)")
        }
    }
    
    @Test("an empty list is valid and means no source")
    func canonicalEmptySourceIsValid() throws {
        // When
        let (document, _) = try Frontmatter.parse(Self.note("[]"))
        
        // Then
        #expect(document.source == [])
    }
    
    // MARK: - Private
    private static func note(_ source: String) -> String {
        """
        ---
        id: fs-note
        title: t
        axis: flow
        priority: lazy
        tags: [flow]
        summary: s
        source: \(source)
        ---

        # body
        """
    }
}
