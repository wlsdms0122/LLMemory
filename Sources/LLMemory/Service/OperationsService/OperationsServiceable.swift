//
//  OperationsServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The write door — every mutation enters as an op payload, is validated
// against its schema, and lands as one transaction or not at all.
//
// The engine is on the contract because it is the op vocabulary itself:
// the names and schemas a caller needs to author a payload, and the
// scope-level apply/dryRun a caller inside an open scope composes with.
protocol OperationsServiceable: Sendable {
    var engine: OperationsEngine { get }

    func apply(
        payloadJSON: String,
        cliSessionId: String
    ) async -> OperationsResult

    func dryRun(
        payloadJSON: String,
        cliSessionId: String
    ) async -> OperationsDryRunResult

    func operationNames() -> [String]

    func operationSchema(_ name: String) -> OperationSchema?
}
