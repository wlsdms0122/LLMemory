//
//  ReferenceMarkerTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// A reference edge is derived from an explicit marker in the body. Prose that happens to contain a
// note's name is not a citation, and a citation whose target does not exist yet is not lost.
@Suite("ReferenceMarker Tests", .serialized)
struct ReferenceMarkerTests {
    // MARK: - Property
    private let home: MemoryHome
    private let links: LinkGraph
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        links = LinkGraph(home)
    }
    
    // MARK: - Test
    @Test("a backticked id is a citation")
    func backtickMarkedIdIsReference() throws {
        // When
        let references = try referencesFrom("see `rm-target` for the detail\n", targets: ["rm-target"])
        
        // Then
        #expect(references == ["rm-target"], "a backticked id must wire a reference — got \(references)")
    }
    
    @Test("a wikilink is a tolerated spelling of the same citation")
    func wikilinkIsToleratedReference() throws {
        // When
        let references = try referencesFrom("see [[rm-target]] here\n", targets: ["rm-target"])
        
        // Then
        #expect(references == ["rm-target"], "[[id]] must wire too — got \(references)")
    }
    
    @Test("a bare mention in prose is not a citation")
    func bareProseMentionIsNotReference() throws {
        // When
        let references = try referencesFrom("the tone of the message is casual\n", targets: ["tone"])
        
        // Then
        #expect(references.isEmpty, "prose must not wire a reference — got \(references)")
    }
    
    @Test("an id that appears only as part of a longer symbol is not a citation")
    func snakeCaseSubstringIsNotReference() throws {
        // When
        let references = try referencesFrom("the `tone_curator` profile drives output\n", targets: ["tone"])
        
        // Then
        #expect(references.isEmpty, "a substring inside a symbol must not wire — got \(references)")
    }
    
    @Test("in a mixed body, only the marked id wires — a file path is not a note id")
    func mixedBodyWiresOnlyMarkedIds() throws {
        // When
        let references = try referencesFrom(
            "core notes: identity/tone via `identity`; see `Feature/principles.swift`\n",
            targets: ["identity", "tone", "principles"]
        )
        
        // Then
        #expect(references == ["identity"], "only the backticked id wires — got \(references)")
    }
    
    @Test("a citation to a note that does not exist yet is kept, and wires when the target arrives")
    func forwardReferenceMaterializesWhenTargetAppears() throws {
        // Given
        try home.reindexFile(at: try home.writeNoteFile(id: "rm-early", body: "see `rm-late` for details\n"))
        
        // Then
        #expect(try links.referenceEdges(from: "rm-early", to: "rm-late") == 0)
        #expect(try links.markers(from: "rm-early", to: "rm-late") == 1,
            "an unresolved citation must persist as a marker")
        
        // When
        try home.reindexFile(at: try home.writeNoteFile(id: "rm-late", body: "# late\n"))
        
        // Then
        #expect(try links.referenceEdges(from: "rm-early", to: "rm-late") == 1,
            "the edge must materialize once the target exists")
    }
    
    @Test("a citation between two notes created in the same transaction wires as well")
    func sameApplyForwardReferenceWires() throws {
        // When
        let result = home.apply([
            [
                "op": "create_note", "id": "rm-first", "axis": "flow", "title": "title",
                "summary": "summary", "tags": ["flow"], "content": "cites `rm-second`\n"
            ],
            [
                "op": "create_note", "id": "rm-second", "axis": "flow", "title": "title",
                "summary": "summary", "tags": ["flow"], "content": "# second\n"
            ]
        ])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try links.referenceEdges(from: "rm-first", to: "rm-second") == 1,
            "a forward citation between siblings in one apply must still wire")
    }
    
    // MARK: - Private
    private func referencesFrom(_ body: String, targets: [String]) throws -> Set<String> {
        for target in targets {
            try home.reindexFile(at: try home.writeNoteFile(id: target, body: "# \(target)\n"))
        }
        
        try home.reindexFile(at: try home.writeNoteFile(id: "rm-src", body: body))
        
        return try home.read { database in
            Set(try String.fetchAll(
                database,
                sql: "SELECT dst FROM note_links WHERE src='rm-src' AND kind='reference'"
            ))
        }
    }
}
