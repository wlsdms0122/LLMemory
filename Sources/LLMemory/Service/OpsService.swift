//
//  OpsService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Ops-domain service — the mutation surface. apply runs the atomic write
// transaction; the op catalog is code-owned and needs no connection.
// The ops contract is "failure is a status, not an exception": connect/lock
// errors are normalized here so callers always get a result envelope.
public enum OpsService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func apply(
        _ storage: GRDBStorage,
        payloadJSON: String,
        sessionId: String? = nil,
        ruleset: String? = nil
    ) async -> OpsEngine.Result {
        do {
            return try await storage.run(
                ApplyOpsTransaction(
                    .init(payloadJSON: payloadJSON, sessionId: sessionId, ruleset: ruleset)
                )
            )
        } catch {
            let rationale = OpsEngine.decodePayload(payloadJSON)?["rationale"] as? String ?? ""

            return OpsEngine.Result(
                status: "failed",
                opResults: [],
                error: "\(error)",
                rejectedIndex: nil,
                rationale: rationale,
                recoveryFailed: []
            )
        }
    }

    public static func dryRun(
        _ storage: GRDBStorage,
        payloadJSON: String,
        ruleset: String? = nil
    ) async -> OpsEngine.DryRunResult {
        do {
            return try await storage.run(
                DryRunOpsTransaction(.init(payloadJSON: payloadJSON, ruleset: ruleset))
            )
        } catch {
            return OpsEngine.DryRunResult(
                status: "rejected",
                opCount: nil,
                error: "\(error)",
                rejectedIndex: nil
            )
        }
    }

    // Code-owned catalog — no connection, no session. Callable directly by any
    // surface (the CLI included).
    public static func opNames() -> [String] {
        Handlers.opNames()
    }

    public static func opSchema(_ name: String) -> OpSchema? {
        Handlers.opSchema(name)
    }

    // MARK: - Private
}
