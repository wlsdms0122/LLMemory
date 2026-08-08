//
//  OpsEngineFixture.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
@testable import LLMemory

// Fixture adapter over the production entry — the payload is serialized to the
// JSON string the CLI would send and applied through the ops transactions'
// sync bodies, so decode and transaction wiring are exercised by every ops
// test. The write lock rides writeLock (the sync gate) because unit tests
// stay synchronous; the async `storage.run` gate is covered by the CLI suite.
extension OpsEngine {
    static func apply(
        _ storage: GRDBStorage,
        _ payload: [String: Any],
        sessionId: String? = nil,
        ruleset: String? = nil
    ) -> Result {
        do {
            let transaction = ApplyOpsTransaction(
                .init(
                    payloadJSON: try Self.encodePayload(payload),
                    sessionId: sessionId,
                    ruleset: ruleset
                )
            )

            return try storage.writeLock {
                transaction.perform(try storage.connect())
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
        do {
            let transaction = DryRunOpsTransaction(
                .init(payloadJSON: try Self.encodePayload(payload), ruleset: ruleset)
            )

            return transaction.perform(try storage.connect())
        } catch {
            return DryRunResult(
                status: "rejected",
                opCount: nil,
                error: "\(error)",
                rejectedIndex: nil
            )
        }
    }

    private static func encodePayload(_ payload: [String: Any]) throws -> String {
        struct EncodeFailure: Error, CustomStringConvertible {
            var description: String { "fixture encode failed: payload is not UTF-8 JSON" }
        }

        let data = try JSONSerialization.data(withJSONObject: payload)

        guard let text = String(data: data, encoding: .utf8) else { throw EncodeFailure() }

        return text
    }
}
