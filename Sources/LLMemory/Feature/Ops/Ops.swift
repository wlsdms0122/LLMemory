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

    // MARK: - Private
}
