//
//  IndexService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// Index-domain service — the async surfaces the tiers above reach for, over
// the scopes the store opens. What a correct projection of the corpus looks
// like is Indexer's judgement, so these bodies orchestrate it directly: a type
// per body would be a name spelled once, at one call site, forwarding to a
// method that already exists.
public struct IndexService: IndexServiceable {
    // MARK: - Property
    let storage: any GRDBStorable
    let brain: BrainContext
    let keywords: any KeywordExtracting

    private let indexer = Indexer()

    // The enrichment keys and defaults have one owner; this resolves them
    // from this brain each time they are needed.
    private var enrichment: EnrichmentTuning { EnrichmentTuning(brain.config) }

    // MARK: - Initializer
    init(storage: any GRDBStorable, brain: BrainContext, keywords: any KeywordExtracting) {
        self.storage = storage
        self.brain = brain
        self.keywords = keywords
    }

    // MARK: - Public
    public func build(
        rebuild: Bool
    ) async throws -> Indexer.BuildResult {
        // The scan runs inside the exclusion boundary — orphan judgement
        // compares scanned paths against DB rows, so a scan taken before the
        // lock could mark a concurrently committed note as an orphan and
        // delete it. Atomicity beats lock duration here.
        try await storage.write { db in
            let scan = indexer.scanPending(brain)

            return try indexer.reconcile(
                brain,
                db,
                pending: scan.pending,
                scannedRels: scan.scannedRels,
                rebuild: rebuild,
                now: Int(Date().timeIntervalSince1970),
                fileErrors: scan.errors
            )
        }
    }

    public func reindex(
        filePaths: [String]
    ) async throws -> [Indexer.ReindexOutcome] {
        try await storage.write { db in
            try indexer.reindexFiles(db, brain, filePaths: filePaths)
        }
    }

    public func check(
        level: Indexer.IntegrityLevel
    ) async throws -> (ok: Bool, msgs: [String]) {
        try await storage.read { db in try indexer.check(db, brain, rawLevel: level.rawValue) }
    }

    public func buildVectors() async throws -> VectorBuildResult {
        try await storage.run(
            BuildVectorsOperation(dimension: brain.config.getInt("vectors.dim", default: 48))
        )
    }

    public func verifySources() async throws -> SourceVerifyResult {
        try await storage.write { db in try SourceVerifier().verifyAll(db, brain) }
    }

    public func validateTerms(
        rejectStale: Bool
    ) async throws -> Indexer.ValidateResult {
        try await storage.run(
            ValidateTermsOperation(
                rejectStale: rejectStale,
                keywords: keywords,
                roundtripTopK: enrichment.roundtripTopK,
                idfDFCeiling: enrichment.idfDFCeiling
            )
        )
    }

    // MARK: - Private
}
