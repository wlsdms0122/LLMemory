//
//  LinksTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Edges come in two families. A learned edge is a statistic that strengthens and decays; a fact edge
// states something the corpus asserts. They are stored the same way and must not be treated the same.
@Suite("Links Tests", .serialized)
struct LinksTests {
    // MARK: - Property
    private let home: MemoryHome
    

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a kind decides its own endpoints — self-loops drop, undirected kinds order")
    func endpointsAreDecidedByTheKind() {
        #expect(LinkKind.assoc.endpoints(src: "a", dst: "a") == nil, "a self-loop must drop")
        #expect(endpoints(of: LinkKind.assoc.endpoints(src: "b", dst: "a")) == ["a", "b"],
            "an undirected assoc canonicalizes to src < dst")
        #expect(endpoints(of: LinkKind.cooccur.endpoints(src: "b", dst: "a")) == ["a", "b"])
        #expect(endpoints(of: LinkKind.cooccur.endpoints(src: "a", dst: "b")) == ["a", "b"],
            "an already-ordered pair is left alone")
        #expect(endpoints(of: LinkKind.reference.endpoints(src: "b", dst: "a")) == ["b", "a"],
            "a directed reference keeps the direction it was given")
    }
    
    @Test("propose_link stores the canonical order, whichever way the caller wrote it")
    func proposeLinkCanonicalViaNormalize() throws {
        // Given
        try seedPair()
        
        // When
        let result = home.apply(["op": "propose_link", "src": "temp-b", "dst": "temp-a", "kind": "assoc"])
        
        // Then
        let row = try home.read { database in
            try Row.fetchOne(database, sql: "SELECT src, dst FROM note_links WHERE kind = 'assoc'")
        }
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(row?["src"] == "temp-a")
        #expect(row?["dst"] == "temp-b")
    }
    
    @Test("propose_link only proposes an association — a fact edge is not the caller's to assert")
    func proposeLinkRejectsNonAssocKind() throws {
        // Given
        try seedPair()
        
        // When
        let result = home.apply([
            "op": "propose_link", "src": "temp-a", "dst": "temp-b", "kind": "reference"
        ])
        
        // Then
        let count = try home.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM note_links
                WHERE kind = 'reference' AND src = 'temp-a' AND dst = 'temp-b'
                """) ?? 0
        }
        
        #expect(result.status != "ok", "a non-assoc kind must be rejected")
        #expect(count == 0, "a rejected op must leave no edge behind")
    }
    
    @Test("strengthening a pair with no edge yet creates one")
    func newLinkCreated() throws {
        // Given
        try seedPair()
        
        // Then
        #expect(try home.database().write { db in try StrengthenLinksTransaction(pairs: [("temp-a", "temp-b")], step: home.genes.double("links.strengthen_step")).perform(db) } == 1)
    }
    
    @Test("strengthening a note against itself does nothing")
    func sameSrcDstSkipped() throws {
        // Given
        try seedPair()
        
        // Then
        #expect(try home.database().write { db in try StrengthenLinksTransaction(pairs: [("temp-a", "temp-a")], step: home.genes.double("links.strengthen_step")).perform(db) } == 0)
    }
    
    @Test("rebirth strengthens the learned edge and leaves the fact edge exactly as it was")
    func rebirthTouchesOnlyLearnedKinds() throws {
        // Given
        try seedPair()
        try home.linkNotes("temp-a", "temp-b", kind: "reference", weight: 0.5)
        try home.linkNotes("temp-a", "temp-b", kind: "cooccur", weight: 0.5)
        
        // When
        _ = try home.database().write { db in try RebirthLinksTransaction(noteIds: ["temp-a", "temp-b"], defaultFactor: home.genes.double("rebirth.default_factor")).perform(db) }
        
        // Then
        let weights = try home.read { database -> [String: Double] in
            let rows = try Row.fetchAll(database, sql: "SELECT kind, weight FROM note_links")
            
            return Dictionary(uniqueKeysWithValues: rows.map { row in
                (row["kind"] as String, row["weight"] as Double)
            })
        }
        
        #expect(weights["cooccur"] ?? 0 > 0.5, "a learned edge must strengthen")
        #expect(weights["reference"] == 0.5, "a fact edge is not something rebirth may touch")
    }
    
    @Test("deleting a note takes its edges with it")
    func cascadeOnNoteDelete() throws {
        // Given
        try seedPair()
        try home.linkNotes("temp-a", "temp-b", kind: "cooccur")
        
        // When
        try home.database().write { database in
            try database.execute(sql: "DELETE FROM notes WHERE id = 'temp-a'")
        }
        
        // Then
        let remaining = try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM note_links WHERE src = 'temp-a' OR dst = 'temp-a'"
            ) ?? 0
        }
        
        #expect(remaining == 0, "the foreign key cascade must reach note_links")
    }
    
    @Test("when every neighbour weighs the same, the cut is decided by id and not by luck")
    func expandCutIsDeterministicOnWeightTies() throws {
        // Given
        let neighbors = (1 ... 6).map { index in "exp-n\(index)" }
        
        try home.seedBareNotes(ids: ["exp-hub"] + neighbors)
        
        for neighbor in neighbors {
            let ordered = ["exp-hub", neighbor].sorted()
            
            try home.linkNotes(ordered[0], ordered[1], kind: "cooccur")
        }
        
        // When
        let expanded = try home.database().read { db in try ExpandLinksTransaction(noteIds: ["exp-hub"], limit: 3, minWeight: home.retrievalTuning.neighborFloor, siblingDiscount: home.retrievalTuning.siblingDiscount).perform(db) }.map(\.id)
        
        // Then
        #expect(expanded == ["exp-n1", "exp-n2", "exp-n3"], "a tie must cut by id ascending — got \(expanded)")
    }
    
    @Test("a sibling edge ranks below a weaker learned one, yet stays an eligible candidate")
    func siblingRanksBelowLearnedAssociationButStaysEligible() throws {
        // Given — the sibling edges are stored at full weight, the learned one at 0.6.
        try home.seedBareNotes(ids: ["sib-hub", "sib-bro1", "sib-bro2", "sib-assoc"])
        try home.linkNotes("sib-bro1", "sib-hub", kind: "sibling")
        try home.linkNotes("sib-hub", "sib-bro2", kind: "sibling")
        try home.linkNotes("sib-assoc", "sib-hub", kind: "cooccur", weight: 0.6)
        
        // When
        let expanded = try home.database().read { db in try ExpandLinksTransaction(noteIds: ["sib-hub"], limit: 3, minWeight: home.retrievalTuning.neighborFloor, siblingDiscount: home.retrievalTuning.siblingDiscount).perform(db) }.map(\.id)
        
        // Then
        #expect(expanded.first == "sib-assoc",
            "a 0.6 learned edge must outrank a 1.0 sibling edge — got \(expanded)")
        #expect(Set(expanded).isSuperset(of: ["sib-bro1", "sib-bro2"]),
            "the discount lowers the rank only — siblings must not drop out: \(expanded)")
    }
    
    // MARK: - Private
    private func seedPair() throws {
        try home.seedBareNotes(ids: ["temp-a", "temp-b"])
    }
    
    private func endpoints(of pair: (src: String, dst: String)?) -> [String]? {
        pair.map { pair in [pair.0, pair.1] }
    }
}
