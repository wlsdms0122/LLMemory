//
//  IndexService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Index-domain service — build/verify surfaces over the write transactions.
public struct IndexService: IndexServiceable {
    // MARK: - Property
    let storage: GRDBStorage
    let brain: BrainContext
    let keywords: any KeywordExtracting

    private let indexer = Indexer()

    // MARK: - Initializer
    init(storage: GRDBStorage, brain: BrainContext, keywords: any KeywordExtracting) {
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
        try await storage.run { scope in
            let scan = indexer.scanPending(brain)

            return try scope.run(
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
        try await storage.run { scope in
            try scope.run(ReindexNotesTransaction(brain: brain, filePaths: filePaths))
        }
    }

    public func check(
        level: Indexer.IntegrityLevel
    ) async throws -> (ok: Bool, msgs: [String]) {
        try await storage.read { scope in try scope.run(CheckIntegrityTransaction(brain: brain, level: level)) }
    }

    public func buildVectors() async throws -> VectorBuildResult {
        try await storage.run { scope in try scope.run(
                BuildVectorsTransaction(dimension: brain.config.getInt("vectors.dim", default: 48))
            ) }
    }

    public func verifySources() async throws -> SourceVerifyResult {
        try await storage.run { scope in try SourceVerifier().verifyAll(scope, brain) }
    }

    public func validateTerms(
        rejectStale: Bool
    ) async throws -> Indexer.ValidateResult {
        try await storage.run { scope in try scope.run(
                ValidateTermsTransaction(
                    rejectStale: rejectStale,
                    keywords: keywords,
                    enrichment: EnrichmentTuning(brain.config)
                )
            ) }
    }

    // MARK: - Private
}
