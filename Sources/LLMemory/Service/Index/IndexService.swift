//
//  IndexService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// Index-domain service — build/verify surfaces over the write transactions.
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

            return try db.run(
                ReconcileIndexTransaction(
                    brain: brain,
                    scan: scan,
                    rebuild: rebuild,
                    now: Int(Date().timeIntervalSince1970)
                )
            )
        }
    }

    public func reindex(
        filePaths: [String]
    ) async throws -> [Indexer.ReindexOutcome] {
        try await storage.write { db in
            try db.run(ReindexNotesTransaction(brain: brain, filePaths: filePaths))
        }
    }

    public func check(
        level: Indexer.IntegrityLevel
    ) async throws -> (ok: Bool, msgs: [String]) {
        try await storage.run(CheckIntegrityTransaction(brain: brain, level: level))
    }

    public func buildVectors() async throws -> VectorBuildResult {
        try await storage.run(
            BuildVectorsTransaction(dimension: brain.config.getInt("vectors.dim", default: 48))
        )
    }

    public func verifySources() async throws -> SourceVerifyResult {
        try await storage.write { db in try SourceVerifier().verifyAll(db, brain) }
    }

    public func validateTerms(
        rejectStale: Bool
    ) async throws -> Indexer.ValidateResult {
        try await storage.run(
            ValidateTermsTransaction(
                rejectStale: rejectStale,
                keywords: keywords,
                roundtripTopK: enrichment.roundtripTopK,
                idfDFCeiling: enrichment.idfDFCeiling
            )
        )
    }

    // MARK: - Private
}
