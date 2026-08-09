//
//  Operations.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct Operations {
    // MARK: - Property
    let session: Session

    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }

    // MARK: - Public
    public func apply(
        payloadJSON: String,
        cliSessionId: String = "",
        ruleset: String? = nil
    ) async -> OperationsEngine.Result {
        await OperationsService.apply(
            session.storage,
            payloadJSON: payloadJSON,
            cliSessionId: cliSessionId,
            ruleset: ruleset
        )
    }

    public func dryRun(
        payloadJSON: String,
        cliSessionId: String = "",
        ruleset: String? = nil
    ) async -> OperationsEngine.DryRunResult {
        await OperationsService.dryRun(
            session.storage,
            payloadJSON: payloadJSON,
            cliSessionId: cliSessionId,
            ruleset: ruleset
        )
    }

    // Catalog reads are code-owned and connection-free; they live on the facade
    // so the CLI has one entry per domain. Constructing Brain for them costs a
    // silently-tolerated warm attempt — lightening the constructor rides the
    // Paths/Config globals debt.
    public func operationNames() -> [String] {
        OperationsService.operationNames()
    }

    public func operationSchema(_ name: String) -> OperationSchema? {
        OperationsService.operationSchema(name)
    }

    // MARK: - Private
}
