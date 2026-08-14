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
// The engine that dispatches those ops is not on the contract. Handing back
// the collaborator would let anyone holding the contract acquire whatever
// the engine holds — the op vocabulary is already here as behaviour
// (`operationNames`/`operationSchema`), and if a scope-level apply is ever
// needed it belongs here as a method, not as the object that has one.
protocol OperationsServiceable: Sendable {
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
