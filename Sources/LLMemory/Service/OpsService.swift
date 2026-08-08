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
public enum OpsService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func apply(
        _ storage: GRDBStorage,
        payloadJSON: String,
        sessionId: String? = nil,
        ruleset: String? = nil
    ) async throws -> OpsEngine.Result {
        try await storage.run(
            ApplyOpsTransaction(
                .init(payloadJSON: payloadJSON, sessionId: sessionId, ruleset: ruleset)
            )
        )
    }

    public static func dryRun(
        _ storage: GRDBStorage,
        payloadJSON: String,
        ruleset: String? = nil
    ) async throws -> OpsEngine.DryRunResult {
        try await storage.run(
            DryRunOpsTransaction(.init(payloadJSON: payloadJSON, ruleset: ruleset))
        )
    }

    public static func opNames() -> [String] {
        Handlers.opNames()
    }

    public static func opSchema(_ name: String) -> OpSchema? {
        Handlers.opSchema(name)
    }

    // MARK: - Private
}
