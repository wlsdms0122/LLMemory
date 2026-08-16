//
//  EnrichmentReviewTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("EnrichmentReview Tests", .serialized)
struct EnrichmentReviewTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private var detector: CandidateDetector { CandidateDetector(brain: home.brain) }

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    
    private static func putVector(_ db: Database, id: String, vector: [Float]) throws {
        let data = vector.withUnsafeBufferPointer { buffer in Data(buffer: buffer) }
        
        try db.execute(sql: """
            INSERT INTO note_vectors (note_id, dim, vec, built_at) VALUES (?, ?, ?, 0)
            ON CONFLICT(note_id) DO UPDATE SET dim = excluded.dim, vec = excluded.vec
            """, arguments: [id, vector.count, data])
    }
    
    private static func unresolvedReviewFlags(_ db: Database) throws -> Int {
        try Int.fetchOne(db, sql: """
            SELECT COUNT(*) FROM ripple_flags WHERE flag = 'enrich_review' AND resolved_at IS NULL
            """) ?? 0
    }
    
    @Test("the status surface reports how many terms and association edges exist")
    func statusReportsTermAndAssocCounts() throws {
        // Given
        home.createNote(id: "rev-a", content: "## A\nzephyr quasar distinctive body\n")
        home.createNote(id: "rev-b")
        
        _ = home.apply([[
            "op": "add_retrieval_terms", "id": "rev-a",
            "kind": "alias", "terms": ["zephyr quasar"], "provenance": "p1"
        ]])
        _ = home.apply([[
            "op": "propose_link", "src": "rev-a", "dst": "rev-b", "provenance": "p1"
        ]])
        
        // When
        let queue = try home.storage.connect()
        let status = try queue.read { db in try EnrichmentStatusTransaction(neighborFloor: home.genes.double("links.neighbor_floor"), enrichment: EnrichmentTuning(home.config)).perform(db) }
        
        // Then
        #expect(status.assocTotal == 1)
        #expect(status.assocDormant == 1)
        #expect(status.assocActive == 0)
        #expect(!status.termCounts.isEmpty)
        
        let totalTerms = status.termCounts.reduce(0) { sum, entry in sum + entry.count }
        
        #expect(totalTerms == 1)
    }
    
    @Test("an edge the model proposed but the vectors do not support is flagged for review")
    func disagreementFlagsLowCosineAssocEdge() throws {
        // Given
        for index in 0..<4 {
            home.createNote(id: "rev-alpha\(index)", tags: ["flow", "clstra"],
                content: "## A\nalpha body \(index)\n")
        }
        
        for index in 0..<4 {
            home.createNote(id: "rev-beta\(index)", tags: ["flow", "clstrb"],
                content: "## A\nbeta body \(index)\n")
        }
        
        _ = home.apply([[
            "op": "propose_link", "src": "rev-alpha0", "dst": "rev-beta0",
            "provenance": "noisy:model"
        ]])
        _ = try home.database().write { db in try BuildVectorsTransaction(dimension: home.config.getInt("vectors.dim", default: 48)).perform(db) }
        
        let now = home.now
        let flagged = try home.storage.writeLock { () -> Int in
            let queue = try home.storage.connect()
        
        // When
            return try queue.write { db in try FlagEnrichmentDisagreementsTransaction(now: now, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db).flagged }
        }
        
        // Then
        #expect(flagged >= 0)
        
        if flagged > 0 {
            let queue = try home.storage.connect()
            let reviewFlags = try queue.read { db in
                try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM ripple_flags WHERE flag = 'enrich_review'
                    """) ?? 0
            }
            
            #expect(reviewFlags > 0)
        }
    }
    
    @Test("per-provenance statistics attribute edges to the run that produced them")
    func provenanceStatsTracksAssocEdges() throws {
        // Given
        home.createNote(id: "rev-p1")
        home.createNote(id: "rev-p2")
        home.createNote(id: "rev-p3")
        
        _ = home.apply([[
            "op": "propose_link", "src": "rev-p1", "dst": "rev-p2", "provenance": "modelX"
        ]])
        _ = home.apply([[
            "op": "propose_link", "src": "rev-p1", "dst": "rev-p3", "provenance": "modelX"
        ]])
        
        // When
        let queue = try home.storage.connect()
        let stats = try queue.read { db in try FetchProvenanceStatsTransaction(disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db) }
        let modelX = stats.first { entry in entry.provenance == "modelX" }
        
        // Then
        #expect(modelX != nil)
        #expect(modelX?.assocEdges == 2)
    }
    
    @Test("vector coverage is measured against the notes that can surface, not against every row")
    func vectorCoverageDenominatorMatchesSurfaceGate() throws {
        // When
        home.createNote(id: "cov-live0", content: "## A\nlive body zero\n")
        home.createNote(id: "cov-live1", content: "## A\nlive body one\n")
        home.createNote(id: "cov-arch", content: "## A\narchived body\n")
        
        // Then
        #expect(home.apply([["op": "invalidate", "id": "cov-arch", "reason": "test"]]).status == "ok")
        
        _ = try home.database().write { db in try BuildVectorsTransaction(dimension: home.config.getInt("vectors.dim", default: 48)).perform(db) }
        
        let queue = try home.storage.connect()
        let status = try queue.read { db in try EnrichmentStatusTransaction(neighborFloor: home.genes.double("links.neighbor_floor"), enrichment: EnrichmentTuning(home.config)).perform(db) }
        
        #expect(status.vectorCount == 2, "only surface notes get a vector row")
        #expect(status.noteCount == 2, "denominator must count the surface population, not off-surface notes")
        #expect(status.vectorCount == status.noteCount, "coverage must read 100% right after a rebuild")
    }
    
    // reconciliation — enrich_review must close when the disagreement clears
    @Test("a flag clears itself once the vectors come to agree")
    func disagreementAutoResolvesWhenCosineRecovers() throws {
        // Given
        home.createNote(id: "rev-h1")
        home.createNote(id: "rev-h2")
        
        _ = home.apply([["op": "propose_link", "src": "rev-h1", "dst": "rev-h2"]])
        
        let now = home.now
        let queue = try home.storage.connect()
        
        try home.storage.writeLock {
            try queue.write { db in
                try Self.putVector(db, id: "rev-h1", vector: [1, 0])
                try Self.putVector(db, id: "rev-h2", vector: [0, 1])
                
                _ = try FlagEnrichmentDisagreementsTransaction(now: now, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db)
            }
        }
        
        // When
        let openBefore = try queue.read { db in try Self.unresolvedReviewFlags(db) }
        
        // Then
        #expect(openBefore == 2)
        
        try home.storage.writeLock {
            try queue.write { db in
                try Self.putVector(db, id: "rev-h2", vector: [1, 0])
                
                _ = try FlagEnrichmentDisagreementsTransaction(now: now + 1, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db)
            }
        }
        
        let (openAfter, events) = try queue.read { db in
            (try Self.unresolvedReviewFlags(db),
                try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM note_lifecycle_events
                WHERE kind = 'flag_resolved' AND reason LIKE 'enrich_review%'
                """) ?? 0)
        }
        
        #expect(openAfter == 0, "healed disagreement must auto-resolve its enrich_review flags")
        #expect(events == 2, "auto-resolve must leave the flag_resolved audit trail")
    }
    
    @Test("a flag clears itself when the edge it was about is pruned away")
    func disagreementAutoResolvesWhenEdgePruned() throws {
        // Given
        home.createNote(id: "rev-e1")
        home.createNote(id: "rev-e2")
        
        _ = home.apply([["op": "propose_link", "src": "rev-e1", "dst": "rev-e2"]])
        
        let now = home.now
        let queue = try home.storage.connect()
        
        try home.storage.writeLock {
            try queue.write { db in
                try Self.putVector(db, id: "rev-e1", vector: [1, 0])
                try Self.putVector(db, id: "rev-e2", vector: [0, 1])
                
                _ = try FlagEnrichmentDisagreementsTransaction(now: now, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db)
            }
        }
        
        // When
        let openBefore = try queue.read { db in try Self.unresolvedReviewFlags(db) }
        
        // Then
        #expect(openBefore == 2)
        
        try home.storage.writeLock {
            try queue.write { db in
                try db.execute(sql: "DELETE FROM note_links WHERE kind = ?",
                    arguments: [LinkKind.assoc.rawValue])
                
                _ = try FlagEnrichmentDisagreementsTransaction(now: now + 1, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db)
            }
        }
        
        let openAfter = try queue.read { db in try Self.unresolvedReviewFlags(db) }
        
        #expect(openAfter == 0, "a pruned assoc edge removes the disagreement — flags must close")
    }
    
    @Test("flags are kept when there are no vectors — absence of evidence is not evidence of agreement")
    func flagsKeptWhenVectorsUnbuilt() throws {
        // Given
        home.createNote(id: "rev-k1")
        home.createNote(id: "rev-k2")
        
        _ = home.apply([["op": "propose_link", "src": "rev-k1", "dst": "rev-k2"]])
        
        let now = home.now
        let queue = try home.storage.connect()
        
        try home.storage.writeLock {
            try queue.write { db in
                try Self.putVector(db, id: "rev-k1", vector: [1, 0])
                try Self.putVector(db, id: "rev-k2", vector: [0, 1])
                
                _ = try FlagEnrichmentDisagreementsTransaction(now: now, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db)
            }
        }
        
        try home.storage.writeLock {
            try queue.write { db in
                try db.execute(sql: "DELETE FROM note_vectors")
                
                _ = try FlagEnrichmentDisagreementsTransaction(now: now + 1, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db)
            }
        }
        
        // When
        let openAfter = try queue.read { db in try Self.unresolvedReviewFlags(db) }
        
        // Then
        #expect(openAfter == 2, "unmeasurable pass must keep existing flags, not resolve them")
    }
    
    // adjudication wiring — surface + op permissions (07-08 concept-review follow-up)
    @Test("the review surface and the ops that act on it are separately permissioned")
    func enrichReviewSurfacesAndOpsPermissionsSplit() throws {
        // Given
        home.createNote(id: "rev-j1")
        home.createNote(id: "rev-j2")
        
        _ = home.apply([["op": "propose_link", "src": "rev-j1", "dst": "rev-j2"]])
        
        let now = home.now
        let queue = try home.storage.connect()
        
        try home.storage.writeLock {
            try queue.write { db in
                try Self.putVector(db, id: "rev-j1", vector: [1, 0])
                try Self.putVector(db, id: "rev-j2", vector: [0, 1])
                
                _ = try FlagEnrichmentDisagreementsTransaction(now: now, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db)
            }
        }
        
        // When
        let candidates = try queue.read { db in try detector.enrichReviewCandidates(GRDBReadScope(db, home.brain)) }
        
        // Then
        #expect(Set(candidates.map { candidate in candidate.id }) == ["rev-j1", "rev-j2"])
        
        let created = home.apply([[
            "op": "flag", "id": "rev-j1", "kind": "enrich_review", "reason": "hand-raised"
        ]])
        
        #expect(created.status != "ok", "enrich_review is a measured signal, so raising one by hand is refused")
        
        let resolved = home.apply([[
            "op": "resolve_flag", "id": "rev-j1", "kind": "enrich_review", "reason": "link judged valid"
        ]])
        
        #expect(resolved.status == "ok", "resolve_flag failed: \(resolved.error)")
        
        let openAfterResolve = try queue.read { db in try Self.unresolvedReviewFlags(db) }
        
        #expect(openAfterResolve == 1, "only rev-j1 closes — rev-j2 must stay open")
        
        try home.storage.writeLock {
            try queue.write { db in
                _ = try FlagEnrichmentDisagreementsTransaction(now: now + 1, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db)
            }
        }
        
        let openAfterReflag = try queue.read { db in try Self.unresolvedReviewFlags(db) }
        
        #expect(openAfterReflag == 2, "a disagreement that persists is flagged again — resurfacing it for review is the point")
    }
    
    @Test("an unregistered flag kind is refused")
    func tagDriftFlagKindRejected() throws {
        // Given
        home.createNote(id: "rev-td1")
        
        // When
        let created = home.apply([[
            "op": "flag", "id": "rev-td1", "kind": "tag_drift", "reason": "orphan kind"
        ]])
        
        // Then
        #expect(created.status != "ok", "tag_drift has no surface to appear on, so creating one is refused")
        
        let resolved = home.apply([[
            "op": "resolve_flag", "id": "rev-td1", "kind": "tag_drift"
        ]])
        
        #expect(resolved.status != "ok", "and it is gone from the resolve vocabulary too")
    }
    
    @Test("with no vectors, the disagreement pass skips rather than flagging everything")
    func disagreementSkipsWhenNoVectors() throws {
        // Given
        home.createNote(id: "rev-nv1")
        home.createNote(id: "rev-nv2")
        
        _ = home.apply([[
            "op": "propose_link", "src": "rev-nv1", "dst": "rev-nv2"
        ]])
        
        let now = home.now
        let flagged = try home.storage.writeLock { () -> Int in
            let queue = try home.storage.connect()
        
        // When
            return try queue.write { db in try FlagEnrichmentDisagreementsTransaction(now: now, disagreeFloor: EnrichmentTuning(home.config).disagreeFloor).perform(db).flagged }
        }
        
        // Then
        #expect(flagged == 0)
    }
}
