//
//  GenomeTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// The genome holds this brain's plasticity parameters. Values resolve through a fixed precedence,
// writes go through exactly two doors, and the homeostatic tick may only react to measured waste.
@Suite("Genome Tests", .serialized)
struct GenomeTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    // The shadow replay borrows a value the genome does not hold. It used to
    // borrow it through a process-wide task-local, which meant every Genes in
    // the task saw it — including another brain's.
    @Test("a borrowed gene value belongs to the replay, not to the brain that lent it")
    func shadowValueDoesNotEscapeTheReplay() throws {
        // Given
        let baseline = home.genes.double("related.expand_hops")

        // When
        let shadowed = home.genes.shadowing("related.expand_hops", baseline + 1)

        // Then
        #expect(shadowed.double("related.expand_hops") == baseline + 1)
        #expect(shadowed.source("related.expand_hops") == "shadow")
        #expect(home.genes.double("related.expand_hops") == baseline,
            "the lending brain's genome must be untouched")
        #expect(home.brain.genes.double("related.expand_hops") == baseline)
    }

    @Test("a shadowed brain tunes only the work it was handed to, and never its own")
    func shadowValueTravelsWithTheTuning() throws {
        // Given
        let baseline = home.genes.double("related.expand_hops")

        // When
        let shadow = home.brain.shadowing(gene: "related.expand_hops", value: baseline + 1)

        // Then
        #expect(RetrievalTuning(shadow.genes).expandHops == Int(baseline) + 1)
        #expect(RetrievalTuning(home.brain.genes).expandHops == Int(baseline),
            "the brain it was derived from must still read its own value")
    }

    @Test("a gene with no row reads as wild-type, config beats wild-type, and a genome row beats both")
    func valueResolution() throws {
        // Then — no row anywhere.
        #expect(home.genes.double("links.sibling_rank_weight") == 0.3)
        #expect(home.genes.source("links.sibling_rank_weight") == "wild_type")
        
        // When — a legacy config value exists.
        try Config.set(home.session, "priming.alpha", value: 0.8)
        
        // Then
        #expect(home.genes.double("priming.alpha") == 0.8)
        #expect(home.genes.source("priming.alpha") == "config")
        
        // When — the genome itself carries a value.
        try home.write { database in
            _ = try database.run(
                ApplyGeneValueTransaction(
                    geneId: "priming.alpha", value: 1.2, cause: "set_gene",
                    requireMutable: false, ts: 1, configured: nil
                )
            )
        }
        
        // Then
        #expect(home.genes.double("priming.alpha") == 1.2)
        #expect(home.genes.source("priming.alpha") == "genome")
    }
    
    @Test("set_gene enforces bounds, refuses an unknown gene, and resets to wild-type without a value")
    func setGeneOp() async throws {
        // When
        let outOfBounds = home.apply(["op": "set_gene", "gene": "links.sibling_rank_weight", "value": 5.0])
        let unknown = home.apply(["op": "set_gene", "gene": "no.such.gene", "value": 0.5])
        let accepted = home.apply([
            "op": "set_gene", "gene": "links.sibling_rank_weight", "value": 0.2, "reason": "test"
        ])
        
        // Then
        #expect(outOfBounds.status != "ok")
        #expect(unknown.status != "ok")
        #expect(accepted.status == "ok")
        #expect(home.genes.double("links.sibling_rank_weight") == 0.2)
        
        let history = try await home.genomeService.history(gene: "links.sibling_rank_weight", limit: 5)
        
        #expect(history.first?.cause == "set_gene", "every change must leave provenance")
        
        // When — value omitted.
        let reset = home.apply(["op": "set_gene", "gene": "links.sibling_rank_weight"])
        
        // Then
        #expect(reset.status == "ok")
        #expect(home.genes.double("links.sibling_rank_weight") == 0.3)
    }
    
    @Test("integer genes reject a fraction, and a boolean is not a number")
    func writeDoorGuards() {
        // When
        let fraction = home.apply(["op": "set_gene", "gene": "related.expand_hops", "value": 1.5])
        let boolean = home.apply(["op": "set_gene", "gene": "priming.alpha", "value": true])
        
        // Then
        #expect(fraction.status != "ok")
        #expect(boolean.status != "ok")
    }

    // Refusing a bool by asking `raw is Bool` refuses the integers 0 and 1 with
    // it — that question is answered by value, not by type, and an integer gene
    // whose bound is 0 or 1 would become unsettable.
    @Test("an integer gene takes an integer value, including one at its bound")
    func writeDoorTakesIntegers() {
        // When
        let one = home.apply(["op": "set_gene", "gene": "related.expand_hops", "value": 1])
        let zero = home.apply(["op": "set_gene", "gene": "rebirth.search_boost", "value": 0])

        // Then
        #expect(one.status == "ok", "unexpected: \(one.error)")
        #expect(zero.status == "ok", "unexpected: \(zero.error)")
    }
    
    @Test("the homeostatic tick cannot move a gene that is not mutable")
    func lockedGeneGuard() throws {
        try home.write { database in
            #expect(throws: GenomeWriteError.self) {
                try database.run(
                    ApplyGeneValueTransaction(
                        geneId: "links.decay_factor", value: 0.8,
                        cause: "homeostasis:test", requireMutable: true, ts: 1, configured: nil
                    )
                )
            }
        }
    }
    
    @Test("expansion that never lands narrows the hop count, and each window is consumed exactly once")
    func homeostasisNarrows() async throws {
        // Given
        home.createNote(id: "seed")
        home.createNote(id: "dead-expand")
        
        try Config.set(home.session, "homeostasis.min_sample", value: 10)
        
        let base = home.now - 50_000
        
        try home.write { database in
            // One get before the window, so the cohort is not blind to whether expansion lands.
            try recordRetrieval(database, timestamp: base - 7200, hitIds: ["seed"], command: "get")
            
            for index in 0 ..< 12 {
                try recordRetrieval(
                    database, timestamp: base + index * 3600,
                    hitIds: ["seed"], expandIds: ["dead-expand"]
                )
            }
            
            _ = try DeriveActivityWindowsTransaction(now: home.now, windowGapSec: home.activationTuning.windowGapSec).perform(database)
            
            // When
            let report = try home.consolidateService.homeostasisTick(database, now: home.now)
            
            // Then
            #expect(report.evaluated)
            #expect(report.adjustedGene == "related.expand_hops")
            #expect(report.newValue == 0)
        }
        
        #expect(home.genes.int("related.expand_hops") == 0)
        
        // When — a second tick over the same history.
        try home.write { database in
            let again = try home.consolidateService.homeostasisTick(database, now: home.now)
            
            // Then
            #expect(again.windowsProcessed == 0, "a window must not be counted twice")
            #expect(again.adjustedGene == nil)
        }
        
        let history = try await home.genomeService.history(gene: "related.expand_hops", limit: 5)
        
        #expect(history.first?.cause == "homeostasis:expand_landing")
    }
    
    @Test("windows recorded before landing was tracked are not evidence — zero there means unmeasured")
    func blindCohortGuard() throws {
        // Given — the same shape as the narrowing case, minus the get that makes landing observable.
        home.createNote(id: "seed")
        home.createNote(id: "dead-expand")
        
        try Config.set(home.session, "homeostasis.min_sample", value: 10)
        
        let base = home.now - 50_000
        
        try home.write { database in
            for index in 0 ..< 12 {
                try recordRetrieval(
                    database, timestamp: base + index * 3600,
                    hitIds: ["seed"], expandIds: ["dead-expand"]
                )
            }
            
            _ = try DeriveActivityWindowsTransaction(now: home.now, windowGapSec: home.activationTuning.windowGapSec).perform(database)
            
            // When
            let report = try home.consolidateService.homeostasisTick(database, now: home.now)
            
            // Then
            #expect(!report.evaluated)
            #expect(report.adjustedGene == nil)
            #expect(report.expandSeen == 0)
        }
        
        #expect(home.genes.int("related.expand_hops") == 1, "the gene must stay at wild-type")
    }
    
    @Test("expansion that lands restores the hop count toward wild-type, and stops there")
    func homeostasisRestores() throws {
        // Given
        home.createNote(id: "seed")
        home.createNote(id: "landed-expand")
        
        try Config.set(home.session, "homeostasis.min_sample", value: 10)
        
        let base = home.now - 50_000
        
        try home.write { database in
            _ = try database.run(
                ApplyGeneValueTransaction(
                    geneId: "related.expand_hops", value: 0, cause: "set_gene",
                    detail: "test setup", requireMutable: false, ts: home.now, configured: nil
                )
            )
            
            for index in 0 ..< 12 {
                let timestamp = base + index * 3600
                
                try recordRetrieval(database, timestamp: timestamp, hitIds: ["seed"], expandIds: ["landed-expand"])
                try recordRetrieval(database, timestamp: timestamp + 30, hitIds: ["landed-expand"], command: "get")
            }
            
            _ = try DeriveActivityWindowsTransaction(now: home.now, windowGapSec: home.activationTuning.windowGapSec).perform(database)
            
            // When
            let report = try home.consolidateService.homeostasisTick(database, now: home.now)
            
            // Then
            #expect(report.evaluated)
            #expect(report.adjustedGene == "related.expand_hops")
            #expect(report.newValue == 1)
        }
        
        // When — more healthy evidence arrives after the gene is already back at wild-type.
        try home.write { database in
            for index in 12 ..< 24 {
                let timestamp = base + index * 1800
                
                try recordRetrieval(database, timestamp: timestamp, hitIds: ["seed"], expandIds: ["landed-expand"])
                try recordRetrieval(database, timestamp: timestamp + 30, hitIds: ["landed-expand"], command: "get")
            }
            
            _ = try DeriveActivityWindowsTransaction(now: home.now, windowGapSec: home.activationTuning.windowGapSec).perform(database)
            
            let report = try home.consolidateService.homeostasisTick(database, now: home.now)
            
            // Then
            #expect(report.adjustedGene == nil, "wild-type is the ceiling — restoration does not overshoot")
        }
        
        #expect(home.genes.int("related.expand_hops") == 1)
    }
    
    @Test("the report states the sample the verdict used, not what happens to be left after it")
    func reportStatesEvaluatedSample() throws {
        // Given
        home.createNote(id: "seed")
        home.createNote(id: "dead-expand")
        
        try Config.set(home.session, "homeostasis.min_sample", value: 10)
        
        let base = home.now - 50_000
        
        try home.write { database in
            try recordRetrieval(database, timestamp: base - 7200, hitIds: ["seed"], command: "get")
            
            for index in 0 ..< 6 {
                try recordRetrieval(
                    database, timestamp: base + index * 3600,
                    hitIds: ["seed"], expandIds: ["dead-expand"]
                )
            }
            
            _ = try DeriveActivityWindowsTransaction(now: home.now, windowGapSec: home.activationTuning.windowGapSec).perform(database)
            
            // When — below the minimum sample.
            let first = try home.consolidateService.homeostasisTick(database, now: home.now)
            
            // Then
            #expect(!first.evaluated)
            #expect(first.sampleSeen == 6)
        }
        
        // When — the evidence accumulates past the minimum.
        try home.write { database in
            for index in 6 ..< 11 {
                try recordRetrieval(
                    database, timestamp: base + index * 3600,
                    hitIds: ["seed"], expandIds: ["dead-expand"]
                )
            }
            
            _ = try DeriveActivityWindowsTransaction(now: home.now, windowGapSec: home.activationTuning.windowGapSec).perform(database)
            
            let second = try home.consolidateService.homeostasisTick(database, now: home.now)
            
            // Then
            #expect(second.evaluated)
            #expect(second.expandSeen == 5, "the cohort this tick consumed")
            #expect(second.sampleSeen == 11, "the whole sample the verdict was made on")
            #expect(second.sampleLanded == 0)
            #expect(second.landingRate == 0)
        }
        
        // When — nothing new since.
        try home.write { database in
            let third = try home.consolidateService.homeostasisTick(database, now: home.now)
            
            // Then
            #expect(third.sampleSeen == 0)
        }
    }
    
    @Test("a stale watermark cache cannot cause a second derivation of the same events")
    func crossProcessWatermark() throws {
        // Given
        home.createNote(id: "n1")
        
        try home.write { database in
            try recordRetrieval(database, timestamp: 3_000_000, hitIds: ["n1"])
            
            _ = try DeriveActivityWindowsTransaction(now: 3_000_100, windowGapSec: home.activationTuning.windowGapSec).perform(database)
        }
        
        // When — the cache is rewound the way a second process would see it.
        home.brain.plantStaleConfigValue("activation.derive_watermark", value: "0")
        
        try home.write { database in
            let result = try DeriveActivityWindowsTransaction(now: 3_000_200, windowGapSec: home.activationTuning.windowGapSec).perform(database)
            
            // Then
            #expect(result.eventsConsumed == 0, "the cursor is read from the row, not from the cache")
        }
        
        let hits = try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM retrieval_hits") ?? 0
        }
        
        #expect(hits == 1)
    }
    
    @Test("a shadow replay isolates the gene change — the same value changes nothing, and it never commits")
    func shadowReplay() async throws {
        // Given
        home.createNote(
            id: "alpha-note", title: "alpha topic", summary: "alpha things",
            content: "## A\nalpha alpha content\n"
        )
        home.createNote(
            id: "beta-note", title: "beta topic", summary: "beta things",
            content: "## A\nbeta beta content\n"
        )
        
        try home.write { database in
            try recordRetrieval(database, timestamp: home.now - 60, hitIds: ["alpha-note"], query: "alpha")
        }
        
        // When
        let unchanged = try await home.genomeService.shadow(
            gene: "priming.alpha", value: home.genes.double("priming.alpha"), limit: 10, sampleDiffs: 5
        )
        
        // Then
        #expect(unchanged.queriesReplayed == 1)
        #expect(unchanged.queriesChanged == 0)
        await #expect(throws: GenomeWriteError.self) {
            _ = try await home.genomeService.shadow(
                gene: "priming.alpha", value: 99, limit: 10, sampleDiffs: 5
            )
        }
        #expect(home.genes.source("priming.alpha") == "wild_type", "a shadow run must not write the gene")
    }
    
    // MARK: - Private
    // Retrieval events are what the genome observes. Written straight into the table so a test can lay
    // down a shaped history without performing the retrievals that would have produced it.
    private func recordRetrieval(
        _ database: Database,
        timestamp: Int,
        hitIds: [String],
        expandIds: [String] = [],
        command: String = "search",
        query: String? = nil
    ) throws {
        var payload: [String: Any] = ["cmd": command, "hit_ids": hitIds, "expand_ids": expandIds]
        
        if let query {
            payload["query"] = query
            payload["limit"] = 5
        }
        
        let json = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        
        try database.execute(
            sql: "INSERT INTO events (ts, kind, session_id, payload) VALUES (?, 'retrieval', NULL, ?)",
            arguments: [timestamp, json]
        )
    }
}
