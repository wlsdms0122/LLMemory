//
//  OpsEngineFixture.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
@testable import LLMemory

// Fixture adapter — production reaches the engine through ApplyOpsTransaction
// (storage.run provides the write lock); unit tests keep the old storage-based
// entry with the same lock discipline.
extension OpsEngine {
    static func apply(
        _ storage: GRDBStorage,
        _ payload: [String: Any],
        sessionId: String? = nil,
        ruleset: String? = nil
    ) -> Result {
        do {
            return try storage.writeLock {
                OpsEngine.apply(
                    try storage.connect(),
                    payload,
                    sessionId: sessionId,
                    ruleset: ruleset
                )
            }
        } catch {
            return Result(
                status: "failed",
                opResults: [],
                error: "\(error)",
                rejectedIndex: nil,
                rationale: payload["rationale"] as? String ?? "",
                recoveryFailed: []
            )
        }
    }

    static func dryRun(
        _ storage: GRDBStorage,
        _ payload: [String: Any],
        ruleset: String? = nil
    ) -> DryRunResult {
        guard let queue = try? storage.connect() else {
            return DryRunResult(
                status: "rejected",
                opCount: nil,
                error: "not connected",
                rejectedIndex: nil
            )
        }

        return OpsEngine.dryRun(queue, payload, ruleset: ruleset)
    }
}
