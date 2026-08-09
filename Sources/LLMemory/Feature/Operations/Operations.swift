//
//  Operations.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct Operations {
    // MARK: - Property
    let operations: OperationsService

    // MARK: - Initializer
    init(operations: OperationsService) {
        self.operations = operations
    }

    // MARK: - Public
    public func apply(
        payloadJSON: String,
        cliSessionId: String = "",
        ruleset: String? = nil
    ) async -> OperationsEngine.Result {
        await operations.apply(
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
        await operations.dryRun(
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
        operations.operationNames()
    }

    public func operationSchema(_ name: String) -> OperationSchema? {
        operations.operationSchema(name)
    }

    // MARK: - Private
}
