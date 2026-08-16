//
//  IndexServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Catalog maintenance — bringing the DB up to what the cortex says, and the
// integrity checks that say whether it got there.
protocol IndexServiceable: Sendable {
    func build(rebuild: Bool) async throws -> Indexer.BuildResult

    func reindex(filePaths: [String]) async throws -> [Indexer.ReindexOutcome]

    func check(level: Indexer.IntegrityLevel) async throws -> (ok: Bool, msgs: [String])

    func buildVectors() async throws -> VectorBuildResult

    func verifySources() async throws -> SourceVerifyResult

    func validateTerms(rejectStale: Bool) async throws -> Indexer.ValidateResult
}
