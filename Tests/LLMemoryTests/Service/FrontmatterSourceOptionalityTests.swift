//
//  FrontmatterSourceOptionalityTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// A source declaration is a list. "No sources" therefore has one spelling — the key is absent — and an
// empty list must converge on it rather than becoming a second way to say the same thing.
@Suite("FrontmatterSourceOptionality Tests", .serialized)
struct FrontmatterSourceOptionalityTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private let frontmatter = Frontmatter()

    private let sourceFingerprint = SourceFingerprint()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("an absent declaration and an empty one round-trip to the same file")
    func absentAndEmptyDeclarationRoundTripIdentically() throws {
        // Given
        let withoutKey = "---\nid: a\ntitle: t\naxis: flow\ntags: [flow]\nsummary: s\n---\n\nbody\n"
        let withEmptyList = "---\nid: a\ntitle: t\naxis: flow\ntags: [flow]\nsummary: s\nsource: []\n---\n\nbody\n"
        
        // When
        let (fromNoKey, _) = try frontmatter.parse(withoutKey)
        let (fromEmptyList, _) = try frontmatter.parse(withEmptyList)
        
        // Then
        #expect(fromNoKey.source == [])
        #expect(fromEmptyList.source == [])
        #expect(!frontmatter.dump(fromNoKey).contains("source:"))
        #expect(!frontmatter.dump(fromEmptyList).contains("source:"), "an empty list must not be written back")
    }
    
    @Test("an empty declaration hashes to nothing, exactly as an absent one does")
    func emptyDeclarationHashesToNothingJustLikeAbsent() {
        #expect(sourceFingerprint.computeFingerprint([]) == nil)
        #expect(sourceFingerprint.computeDeclHash([]) == nil)
    }
    
    @Test("a split child inherits an empty basis without inventing a key for it")
    func splitChildInheritsAnEmptyBasisWithoutInventingOne() throws {
        // Given
        home.createNote(id: "sp-parent", content: "## A\nx\n## B\ny\n")
        
        // When
        let result = home.apply(["op": "split_note", "from_id": "sp-parent", "into": [
            [
                "id": "sp-c1", "title": "c1", "tags": ["flow"],
                "summary": "summary", "sections": ["## A"]
            ],
            [
                "id": "sp-c2", "title": "c2", "tags": ["flow"],
                "summary": "summary", "sections": ["## B"]
            ]
        ]])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        
        for childId in ["sp-c1", "sp-c2"] {
            let text = try home.bodyText(of: childId)
            
            #expect(!text.contains("source:"), "\(childId) was handed an empty basis spelled as a key")
            #expect(try frontmatter.parse(text).0.source == [])
        }
    }
}
