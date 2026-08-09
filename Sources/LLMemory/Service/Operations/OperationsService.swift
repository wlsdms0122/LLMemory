//
//  OperationsService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Ops-domain service — the mutation surface. apply runs the atomic write
// transaction; the op catalog is code-owned and needs no connection.
// The ops contract is "failure is a status, not an exception": connect/lock
// errors are normalized here as "unavailable" — a first-class state distinct
// from "failed" (ran and rolled back) and "rejected" (payload refused),
// because nothing was executed and the payload was never interpreted.
public enum OperationsService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func apply(
        _ storage: GRDBStorage,
        payloadJSON: String,
        cliSessionId: String = "",
        ruleset: String? = nil
    ) async -> OperationsEngine.Result {
        // Session resolution happens here, below every surface, with the
        // sibling services' convention: the CLI override wins, the
        // environment is the fallback — so the observation policy never
        // silently loses its session filter.
        let sessionId = Env.retrievalSession(cli: cliSessionId)

        // Shape rejection happens before any lock — a malformed payload must
        // not open the write scope. The string is decoded again inside the
        // scope because [String: Any] cannot cross the Sendable wall.
        guard OperationsEngine.decodePayload(payloadJSON) != nil else {
            return OperationsEngine.Result(
                status: "rejected",
                opResults: [],
                error: "payload must be a JSON object",
                rejectedIndex: nil,
                rationale: "",
                recoveryFailed: []
            )
        }

        do {
            let result = try await storage.run { scope in
                guard let payload = OperationsEngine.decodePayload(payloadJSON) else {
                    return OperationsEngine.Result(
                        status: "rejected",
                        opResults: [],
                        error: "payload must be a JSON object",
                        rejectedIndex: nil,
                        rationale: "",
                        recoveryFailed: []
                    )
                }

                return OperationsEngine.apply(scope, payload, sessionId: sessionId, ruleset: ruleset)
            }

            return result
        } catch {
            // Nothing ran (connect/lock failure) — the cache was never primed.
            return OperationsEngine.Result(
                status: "unavailable",
                opResults: [],
                error: "\(error)",
                rejectedIndex: nil,
                rationale: "",
                recoveryFailed: []
            )
        }
    }

    public static func dryRun(
        _ storage: GRDBStorage,
        payloadJSON: String,
        cliSessionId: String = "",
        ruleset: String? = nil
    ) async -> OperationsEngine.DryRunResult {
        let sessionId = Env.retrievalSession(cli: cliSessionId)

        do {
            return try await storage.read { scope in
                guard let payload = OperationsEngine.decodePayload(payloadJSON) else {
                    return OperationsEngine.DryRunResult(
                        status: "rejected",
                        opCount: nil,
                        error: "payload must be a JSON object",
                        rejectedIndex: nil
                    )
                }

                return OperationsEngine.dryRun(scope, payload, sessionId: sessionId, ruleset: ruleset)
            }
        } catch {
            return OperationsEngine.DryRunResult(
                status: "unavailable",
                opCount: nil,
                error: "\(error)",
                rejectedIndex: nil
            )
        }
    }

    // Code-owned catalog — no connection, no session. Callable directly by any
    // surface (the CLI included).
    public static func operationNames() -> [String] {
        Handlers.operationNames()
    }

    public static func operationSchema(_ name: String) -> OperationSchema? {
        Handlers.operationSchema(name)
    }

    // MARK: - Private
}
