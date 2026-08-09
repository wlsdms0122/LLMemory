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
        try await storage.run(BuildIndexTransaction(.init(rebuild: rebuild)))
    }

    @discardableResult
    public static func reindex(
        _ storage: GRDBStorage,
        filePaths: [String]
    ) async throws -> Int {
        try await storage.run(ReindexNotesTransaction(.init(filePaths: filePaths)))
    }

    public static func check(
        _ storage: GRDBStorage,
        level: Indexer.IntegrityLevel = .l1
    ) async throws -> (ok: Bool, msgs: [String]) {
        try await storage.run(CheckIntegrityTransaction(.init(level: level)))
    }

    public static func buildVectors(_ storage: GRDBStorage) async throws -> Vectors.BuildResult {
        try await storage.run(BuildVectorsTransaction())
    }

    public static func verifySources(_ storage: GRDBStorage) async throws -> SourceVerifyResult {
        try await storage.run { scope in try scope.run(VerifySourcesTransaction()) }
    }

    public static func validateTerms(
        _ storage: GRDBStorage,
        rejectStale: Bool
    ) async throws -> Indexer.ValidateResult {
        try await storage.run(ValidateTermsTransaction(.init(rejectStale: rejectStale)))
    }

    // MARK: - Private
}
