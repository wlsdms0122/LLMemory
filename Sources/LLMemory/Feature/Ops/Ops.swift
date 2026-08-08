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
        _ payload: [String: Any],
        sessionId: String? = nil,
        ruleset: String? = nil
    ) -> OpsTransaction.Result {
        OpsTransaction.apply(session.storage, payload, sessionId: sessionId, ruleset: ruleset)
    }

    public func dryRun(
        _ payload: [String: Any],
        ruleset: String? = nil
    ) -> OpsTransaction.DryRunResult {
        OpsTransaction.dryRun(session.storage, payload, ruleset: ruleset)
    }

    // MARK: - Private
}
