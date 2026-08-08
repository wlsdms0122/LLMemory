//
//  VectorsTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory
@Suite("Vectors Tests", .serialized)
struct VectorsTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    
    @Test("a corpus too small to factorize is skipped rather than fitted to noise")
    func buildSkipsWithTooFewNotes() throws {
        // Given
        home.createNote(id: "vec-only1")
        
        // When
        let result = try Vectors.build()
        
        // Then
        #expect(result.skipped)
    }
    
    @Test("a build produces the vectors and records what it built them from")
    func buildProducesVectorsAndMeta() throws {
        // Given
        for index in 0..<6 {
            home.createNote(id: "vec-n\(index)", tags: ["flow", index < 3 ? "groupa" : "groupb"],
                content: "## A\nshared body content number \(index)\n")
        }
        
        // When
        let result = try Vectors.build()
        
        // Then
        #expect(!result.skipped)
        #expect(result.noteCount == 6)
        #expect(result.dim >= 1 && result.dim <= 5)
        
        let queue = try GRDBStorage.session.connect()
        let vectorCount = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_vectors") ?? 0
        }
        
        #expect(vectorCount == 6)
        
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT dim, vec FROM note_vectors LIMIT 1")
        }
        let dimension: Int = row?["dim"] ?? 0
        let blob: Data = row?["vec"] ?? Data()
        
        #expect(blob.count == dimension * 4)
        
        let model = try queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'vectors.model'")
        }
        
        #expect(model == "ppmi-svd")
    }
    
    @Test("expansion surfaces a note that shares no keyword but sits close in the graph")
    func expandFindsTagSiblings() throws {
        // Given
        for index in 0..<4 {
            home.createNote(id: "vec-a\(index)", tags: ["flow", "clusteralpha"],
                content: "## A\nalpha cluster body \(index)\n")
        }
        
        for index in 0..<4 {
            home.createNote(id: "vec-b\(index)", tags: ["flow", "clusterbeta"],
                content: "## A\nbeta cluster body \(index)\n")
        }
        
        _ = try Vectors.build()
        
        // When
        let hits = try Vectors.expand(seedIds: ["vec-a0"], limit: 8)
        
        // Then
        #expect(!hits.isEmpty)
        
        if let top = hits.first {
            #expect(top.id.hasPrefix("vec-a"))
        }
    }
    
    @Test("with no vectors built, expansion returns nothing rather than falling back")
    func expandReturnsEmptyWhenNoVectors() throws {
        // Given
        home.createNote(id: "vec-x1")
        home.createNote(id: "vec-x2")
        
        // When
        let hits = try Vectors.expand(seedIds: ["vec-x1"], limit: 5)
        
        // Then
        #expect(hits.isEmpty)
    }
    
    @Test("PPMI is non-negative by construction")
    func ppmiIsNonNegative() throws {
        // When
        let matrix: [Double] = [
            0, 2, 1,
            2, 0, 3,
            1, 3, 0
        ]
        let ppmi = Vectors.computePPMI(matrix, n: 3)
        
        // Then
        #expect(ppmi.allSatisfy { value in value >= 0 })
    }
    
    @Test("the truncated decomposition has the shape it was asked for, and every value is finite")
    func svdOrthonormalShape() throws {
        // When
        let dimension = 4, rank = 2
        let matrix: [Double] = [
            1.0, 0.5, 0.1, 0.0,
            0.5, 1.0, 0.2, 0.1,
            0.1, 0.2, 1.0, 0.6,
            0.0, 0.1, 0.6, 1.0
        ]
        let decomposed = try Vectors.truncatedSVD(matrix, n: dimension, k: rank)
        
        // Then
        #expect(decomposed.count == dimension * rank)
        #expect(decomposed.allSatisfy { value in value.isFinite })
    }
    
    @Test("a stale note is excluded before scoring, not filtered out of the answer afterwards")
    func expandExcludesStaleBeforeScoring() throws {
        // Given
        for index in 0..<5 {
            home.createNote(id: "vg-act-\(index)", tags: ["flow", "vggroup"],
                content: "## A\nactive gate body \(index)\n")
        }
        
        for index in 0..<2 {
            home.createNote(id: "vg-arc-\(index)", tags: ["flow", "vggroup"],
                content: "## A\narchived gate body \(index)\n")
        }
        
        home.createNote(id: "vg-stl-0", tags: ["flow", "vggroup"],
            content: "## A\nstale gate body 0\n")
        
        let queue = try GRDBStorage.session.connect()
        
        try queue.write { db in
            try db.execute(sql: "UPDATE notes SET stale = 1 WHERE id IN ('vg-arc-0', 'vg-arc-1')")
            try db.execute(sql: "UPDATE notes SET stale = 1 WHERE id = 'vg-stl-0'")
        }
        
        _ = try Vectors.build()
        
        // When
        let hits = try Vectors.expand(seedIds: ["vg-act-0"], limit: 5)
        
        // Then
        #expect(hits.count == 4)
        #expect(!hits.contains(where: { hit in hit.id.hasPrefix("vg-arc-") || hit.id.hasPrefix("vg-stl-") }))
    }
    
    @Test("when two candidates score the same, the cut is decided by id rather than by luck")
    func expandCutIsDeterministicOnCosineTies() throws {
        // Given
        let others = ["vt-n1", "vt-n2", "vt-n3", "vt-n4", "vt-n5", "vt-n6"]
        
        for noteId in ["vt-n0"] + others {
            home.createNote(id: noteId, tags: ["flow", "vtgroup"],
                content: "## A\ntie body \(noteId)\n")
        }
        
        let vector: [Float] = [0.6, 0.8, 0, 0]
        let blob = vector.withUnsafeBufferPointer { buffer in Data(buffer: buffer) }
        let now = home.now
        let queue = try GRDBStorage.session.connect()
        
        try queue.write { db in
            for noteId in ["vt-n0"] + others {
                try db.execute(sql: """
                    INSERT INTO note_vectors (note_id, dim, vec, built_at)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [noteId, vector.count, blob, now])
            }
        }
        
        // When
        let got = try Vectors.expand(seedIds: ["vt-n0"], limit: 3).map { hit in hit.id }
        
        // Then
        #expect(got == ["vt-n1", "vt-n2", "vt-n3"],
            "a cosine tie must cut by id ascending — got \(got)")
    }
    
    @Test("a stale note is kept out of the matrix, so it cannot shape the space")
    func buildExcludesStaleFromMatrix() throws {
        // Given
        for index in 0..<4 {
            home.createNote(id: "vb-act-\(index)", tags: ["flow", "vbgroup"],
                content: "## A\nactive build body \(index)\n")
        }
        
        home.createNote(id: "vb-arc-0", tags: ["flow", "vbgroup"],
            content: "## A\narchived build body\n")
        home.createNote(id: "vb-stl-0", tags: ["flow", "vbgroup"],
            content: "## A\nstale build body\n")
        
        let queue = try GRDBStorage.session.connect()
        
        try queue.write { db in
            try db.execute(sql: "UPDATE notes SET stale = 1 WHERE id = 'vb-arc-0'")
            try db.execute(sql: "UPDATE notes SET stale = 1 WHERE id = 'vb-stl-0'")
        }
        
        // When
        let result = try Vectors.build()
        
        // Then
        #expect(result.noteCount == 4)
        
        let vectorIds = try queue.read { db in
            try String.fetchAll(db, sql: "SELECT note_id FROM note_vectors ORDER BY note_id")
        }
        
        #expect(vectorIds == ["vb-act-0", "vb-act-1", "vb-act-2", "vb-act-3"])
        #expect(!vectorIds.contains(where: { id in id.hasPrefix("vb-arc-") || id.hasPrefix("vb-stl-") }))
    }
}
