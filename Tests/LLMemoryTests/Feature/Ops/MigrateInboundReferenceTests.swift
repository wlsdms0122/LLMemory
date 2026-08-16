//
//  MigrateInboundReferenceTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// A reference edge is derived from the marker written in the body, so re-addressing a note has to
// move the markers themselves — there is no alias table standing between the citation and the id.
@Suite("MigrateInboundReference Tests", .serialized)
struct MigrateInboundReferenceTests {
    // MARK: - Property
    private let home: MemoryHome
    private let links: LinkGraph
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        links = LinkGraph(home)
    }
    
    // MARK: - Test
    @Test("re-addressing a cited note rewrites the citations, so no edge is lost and none dangles")
    func migrateRewritesInboundCitations() throws {
        // Given
        try home.reindexFile(at: try home.writeNoteFile(id: "target-note", body: "# body"))
        try home.reindexFile(at: try home.writeNoteFile(
            id: "referrer",
            body: "see [[target-note]] and `target-note` for context"
        ))
        
        #expect(try links.referenceEdges(from: "referrer", to: "target-note") == 1,
            "setup: referrer should reference target-note")
        
        // When
        let migrated = home.apply([
            "op": "migrate_note", "id": "target-note", "new_id": "flow.new-note"
        ])
        
        // Then
        #expect(migrated.status == "ok", "\(migrated.error)")
        #expect(try links.referenceEdges(from: "referrer", to: "flow.new-note") == 1,
            "the edge must follow the note to its new address")
        #expect(try links.edges(pointingAt: "target-note") == 0, "no edge may point at the retired id")
        #expect(try links.markers(from: "referrer", to: "target-note") == 0,
            "the old marker must be gone from the body, not merely unresolved")
        #expect(try links.unresolvedStaleReferenceFlags(on: "referrer") == 0,
            "a rewritten citation is not stale, so the referrer must not be flagged")
        
        let body = try String(
            contentsOf: home.url.appendingPathComponent(home.paths.relativeFile(forId: "referrer")),
            encoding: .utf8
        )
        
        #expect(body.contains("[[flow.new-note]]"), "the wikilink form must be rewritten")
        #expect(body.contains("`flow.new-note`"), "the backtick form must be rewritten too")
        #expect(!body.contains("target-note"), "no spelling of the old id may survive")
    }
    
    @Test("a rolled-back transaction puts the rewritten citations back too")
    func rolledBackMigrateRestoresCitingFiles() throws {
        // Given
        try home.reindexFile(at: try home.writeNoteFile(id: "roll-target", body: "# body"))
        try home.reindexFile(at: try home.writeNoteFile(
            id: "roll-citer",
            body: "see [[roll-target]] for context"
        ))
        
        let citer = home.url.appendingPathComponent(home.paths.relativeFile(forId: "roll-citer"))
        let before = try String(contentsOf: citer, encoding: .utf8)
        
        // When — the migrate succeeds, then a second op fails the transaction.
        // The citing file is not the op's own target, so only `touches` naming it
        // keeps it in the snapshot.
        let result = home.apply([
            ["op": "migrate_note", "id": "roll-target", "new_id": "flow.roll-target"],
            ["op": "migrate_note", "id": "no-such-note", "new_id": "flow.nope"]
        ])
        
        // Then
        #expect(result.status != "ok")
        #expect(try String(contentsOf: citer, encoding: .utf8) == before,
            "the citation stayed rewritten although the transaction rolled back")
    }
    
    @Test("a note nobody cites is re-addressed without touching any other file")
    func migrateWithoutCitationsTouchesNothingElse() throws {
        // Given
        try home.reindexFile(at: try home.writeNoteFile(id: "lonely", body: "# body"))
        try home.reindexFile(at: try home.writeNoteFile(id: "bystander", body: "unrelated body"))
        
        let bystander = home.url.appendingPathComponent(home.paths.relativeFile(forId: "bystander"))
        let before = try String(contentsOf: bystander, encoding: .utf8)
        
        // When
        let migrated = home.apply(["op": "migrate_note", "id": "lonely", "new_id": "flow.lonely"])
        
        // Then
        #expect(migrated.status == "ok", "\(migrated.error)")
        #expect(try String(contentsOf: bystander, encoding: .utf8) == before)
    }
}
