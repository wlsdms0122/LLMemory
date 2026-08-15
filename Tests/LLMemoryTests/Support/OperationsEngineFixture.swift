//
//  OperationsEngineFixture.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB
@testable import LLMemory

// Fixture adapter over the production entry — the payload is serialized to the
// JSON string the CLI would send, decoded through the service's single decode
// door, and applied through the engine's scope body. The write lock rides
// writeLock (the sync gate) because unit tests stay synchronous; the async
// `storage.run` gate is covered by the CLI suite.
extension OperationsEngine {
    static func apply(
        _ storage: GRDBStorage,
        _ payload: [String: Any],
        sessionId: String? = nil
    ) -> OperationsResult {
        do {
            let json = try Self.encodePayload(payload)
            let engine = OperationsEngine(lint: LintScanner(rules: LintRuleRegistry()), keywords: FrequencyKeywords())

            guard let decoded = engine.decodePayload(json) else {
                return OperationsResult(
                    status: "rejected",
                    opResults: [],
                    error: "payload must be a JSON object",
                    rejectedIndex: nil,
                    rationale: "",
                    recoveryFailed: []
                )
            }

            return try storage.writeLock {
                try storage.connect().write { db in
                    engine.apply(GRDBScope(db), decoded, sessionId: sessionId)
                }
            }
        } catch {
            return OperationsResult(
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
        _ payload: [String: Any]
    ) -> OperationsDryRunResult {
        do {
            let json = try Self.encodePayload(payload)
            let engine = OperationsEngine(lint: LintScanner(rules: LintRuleRegistry()), keywords: FrequencyKeywords())

            guard let decoded = engine.decodePayload(json) else {
                return OperationsDryRunResult(
                    status: "rejected",
                    opCount: nil,
                    error: "payload must be a JSON object",
                    rejectedIndex: nil
                )
            }

            return try storage.connect().read { db in
                engine.dryRun(GRDBReadScope(db), decoded)
            }
        } catch {
            return OperationsDryRunResult(
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
