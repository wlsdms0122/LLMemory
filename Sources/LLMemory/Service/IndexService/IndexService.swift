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

    private let indexer = Indexer()

    // MARK: - Initializer
    init(storage: GRDBStorage) {
        self.storage = storage
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
            let scan = indexer.scanPending()

            return try scope.run(
                ReconcileIndexTransaction(
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
            try scope.run(ReindexNotesTransaction(filePaths: filePaths))
        }
    }

    public func check(
        level: Indexer.IntegrityLevel
    ) async throws -> (ok: Bool, msgs: [String]) {
        try await storage.read { scope in try scope.run(CheckIntegrityTransaction(level: level)) }
    }

    public func buildVectors() async throws -> VectorBuildResult {
        try await storage.run { scope in try scope.run(BuildVectorsTransaction()) }
    }

    public func verifySources() async throws -> SourceVerifyResult {
        try await storage.run { scope in try scope.run(VerifySourcesTransaction()) }
    }

    public func validateTerms(
        rejectStale: Bool
    ) async throws -> Indexer.ValidateResult {
        try await storage.run { scope in try scope.run(ValidateTermsTransaction(rejectStale: rejectStale)) }
    }

    // MARK: - Private
}
