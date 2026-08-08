//
//  SectionGetTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import GRDB
@testable import LLMemory

// Reading part of a note is how a long one stays affordable. The slice has to be the subtree the
// caller named, and a path that does not exist has to say so rather than come back empty.
@Suite("SectionGet Tests", .serialized)
struct SectionGetTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("asking for a section returns it with its children and nothing from its siblings")
    func getSectionsSlicesSubtree() throws {
        // Given
        #expect(home.createNote(
            id: "doc", axis: "tech", title: "doc", tags: ["tech"],
            content: "## A\na-body\n### A1\na1-body\n## B\nb-body\n"
        ).status == "ok")
        
        // When
        let (note, slices) = try Retrieval.getSections(home.database(), id: "doc", sections: ["## A"])
        
        // Then
        #expect(note.id == "doc")
        #expect(slices.count == 1)
        #expect(slices[0].path == "## A")
        #expect(slices[0].text.contains("a1-body"), "the subtree comes with the section")
        #expect(!slices[0].text.contains("b-body"), "a sibling's body must not come along")
    }
    
    @Test("asking for a section that does not exist throws instead of returning nothing")
    func getSectionsUnknownPathFailsLoud() throws {
        // Given
        #expect(home.createNote(id: "doc2", axis: "tech", tags: ["tech"], content: "## A\nbody\n")
            .status == "ok")
        
        // Then
        #expect(throws: SectionError.self) {
            _ = try Retrieval.getSections(home.database(), id: "doc2", sections: ["## Nope"])
        }
    }
    
    @Test("the table of contents lists every path with the word count that decides what to read")
    func tocListsPathsAndWords() throws {
        // Given
        #expect(home.createNote(
            id: "doc3", axis: "tech", tags: ["tech"],
            content: "## A\none two three\n### A1\nfour\n"
        ).status == "ok")
        
        // When
        let (_, entries) = try Retrieval.toc(home.database(), id: "doc3")
        
        // Then
        #expect(entries.map(\.path) == ["## A", "## A > ### A1"])
        #expect(entries[0].words == 5)
        #expect(entries[1].words == 3)
    }
}
