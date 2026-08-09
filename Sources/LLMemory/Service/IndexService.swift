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
        // The corpus scan (file I/O, parsing) runs before the lock — only the
        // reconcile holds the write scope.
        let scan = Indexer.scanPending()
        let now = Int(Date().timeIntervalSince1970)

        return try await storage.run { scope in
            try scope.run(ReconcileIndexTransaction(scan: scan, rebuild: rebuild, now: now))
        }
    }

    @discardableResult
    public static func reindex(
        _ storage: GRDBStorage,
        filePaths: [String]
    ) async throws -> Int {
        let outcomes = try await storage.run { scope in
            try scope.run(ReindexNotesTransaction(filePaths: filePaths))
        }

        // Emission after the scope commits — "printed" means "committed".
        return Indexer.ReindexOutcome.emit(outcomes)
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
