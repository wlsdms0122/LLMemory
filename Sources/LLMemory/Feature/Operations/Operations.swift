//
//  Operations.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

public struct Operations {
    // MARK: - Property
    let service: OperationsService

    // MARK: - Initializer
    init(service: OperationsService) {
        self.service = service
    }

    // MARK: - Public
    public func apply(
        payloadJSON: String,
        cliSessionId: String = "",
        ruleset: String? = nil
    ) async -> OperationsResult {
        await service.apply(
            payloadJSON: payloadJSON,
            cliSessionId: cliSessionId,
            ruleset: ruleset
        )
    }

    public func dryRun(
        payloadJSON: String,
        cliSessionId: String = "",
        ruleset: String? = nil
    ) async -> OperationsDryRunResult {
        await service.dryRun(
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
        service.operationNames()
    }

    public func operationSchema(_ name: String) -> OperationSchema? {
        service.operationSchema(name)
    }

    // MARK: - Private
}
