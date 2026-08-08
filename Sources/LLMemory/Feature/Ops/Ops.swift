//
//  Ops.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct Ops {
    // MARK: - Property
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public
    public func apply(
        payloadJSON: String,
        sessionId: String? = nil,
        ruleset: String? = nil
    ) async -> OpsEngine.Result {
        await OpsService.apply(
            session.storage,
            payloadJSON: payloadJSON,
            sessionId: sessionId,
            ruleset: ruleset
        )
    }

    public func dryRun(
        payloadJSON: String,
        ruleset: String? = nil
    ) async -> OpsEngine.DryRunResult {
        await OpsService.dryRun(session.storage, payloadJSON: payloadJSON, ruleset: ruleset)
    }

    // Catalog reads are code-owned and connection-free; they live on the facade
    // so the CLI has one entry per domain. Constructing Brain for them costs a
    // silently-tolerated warm attempt — lightening the constructor rides the
    // Paths/Config globals debt.
    public func opNames() -> [String] {
        OpsService.opNames()
    }

    public func opSchema(_ name: String) -> OpSchema? {
        OpsService.opSchema(name)
    }

    // MARK: - Private
}
