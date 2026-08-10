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
public struct OperationsService: Sendable {
    // MARK: - Property
    let storage: GRDBStorage
    let engine: OperationsEngine

    // MARK: - Initializer
    init(storage: GRDBStorage, engine: OperationsEngine) {
        self.storage = storage
        self.engine = engine
    }

    // MARK: - Public
    public func apply(
        payloadJSON: String,
        cliSessionId: String = ""
    ) async -> OperationsResult {
        // Session resolution happens here, below every surface, with the
        // sibling services' convention: the CLI override wins, the
        // environment is the fallback — so the observation policy never
        // silently loses its session filter.
        let sessionId = Environment.retrievalSession(cli: cliSessionId)

        // Shape rejection happens before any lock — a malformed payload must
        // not open the write scope. The string is decoded again inside the
        // scope because [String: Any] cannot cross the Sendable wall.
        guard OperationsEngine.decodePayload(payloadJSON) != nil else {
            return OperationsResult(
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
                    return OperationsResult(
                        status: "rejected",
                        opResults: [],
                        error: "payload must be a JSON object",
                        rejectedIndex: nil,
                        rationale: "",
                        recoveryFailed: []
                    )
                }

                return engine.apply(scope, payload, sessionId: sessionId)
            }

            return result
        } catch {
            // Nothing ran (connect/lock failure) — the cache was never primed.
            return OperationsResult(
                status: "unavailable",
                opResults: [],
                error: "\(error)",
                rejectedIndex: nil,
                rationale: "",
                recoveryFailed: []
            )
        }
    }

    public func dryRun(
        payloadJSON: String,
        cliSessionId: String = ""
    ) async -> OperationsDryRunResult {
        let sessionId = Environment.retrievalSession(cli: cliSessionId)

        do {
            return try await storage.read { scope in
                guard let payload = OperationsEngine.decodePayload(payloadJSON) else {
                    return OperationsDryRunResult(
                        status: "rejected",
                        opCount: nil,
                        error: "payload must be a JSON object",
                        rejectedIndex: nil
                    )
                }

                return engine.dryRun(scope, payload, sessionId: sessionId)
            }
        } catch {
            return OperationsDryRunResult(
                status: "unavailable",
                opCount: nil,
                error: "\(error)",
                rejectedIndex: nil
            )
        }
    }

    // Code-owned catalog — no connection, no session. Callable directly by any
    // surface (the CLI included).
    public func operationNames() -> [String] {
        engine.operationNames()
    }

    public func operationSchema(_ name: String) -> OperationSchema? {
        engine.operationSchema(name)
    }

    // MARK: - Private
}
