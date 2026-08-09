//
//  IndexService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Index-domain service — build/verify surfaces over the write transactions.
public enum IndexService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func build(
        _ storage: GRDBStorage,
        rebuild: Bool = false
    ) async throws -> Indexer.BuildResult {
        // The scan runs inside the exclusion boundary — orphan judgement
        // compares scanned paths against DB rows, so a scan taken before the
        // lock could mark a concurrently committed note as an orphan and
        // delete it. Atomicity beats lock duration here.
        try await storage.run { scope in
            let scan = Indexer.scanPending()

            return try scope.run(
                ReconcileIndexTransaction(
                    scan: scan,
                    rebuild: rebuild,
                    now: Int(Date().timeIntervalSince1970)
                )
            )
        }
    }

    public static func reindex(
        _ storage: GRDBStorage,
        filePaths: [String]
    ) async throws -> [Indexer.ReindexOutcome] {
        try await storage.run { scope in
            try scope.run(ReindexNotesTransaction(filePaths: filePaths))
        }
    }

    public static func check(
        _ storage: GRDBStorage,
        level: Indexer.IntegrityLevel = .l1
    ) async throws -> (ok: Bool, msgs: [String]) {
        try await storage.read { scope in try scope.run(CheckIntegrityTransaction(level: level)) }
    }

    public static func buildVectors(_ storage: GRDBStorage) async throws -> VectorBuildResult {
        try await storage.run { scope in try scope.run(BuildVectorsTransaction()) }
    }

    public static func verifySources(_ storage: GRDBStorage) async throws -> SourceVerifyResult {
        try await storage.run { scope in try scope.run(VerifySourcesTransaction()) }
    }

    public static func validateTerms(
        _ storage: GRDBStorage,
        rejectStale: Bool
    ) async throws -> Indexer.ValidateResult {
        try await storage.run { scope in try scope.run(ValidateTermsTransaction(rejectStale: rejectStale)) }
    }

    // MARK: - Private
}
