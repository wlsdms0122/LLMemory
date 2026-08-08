//
//  DryRunOpsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage
import GRDB

// Validation of an ops payload without persisting — a read, so it never takes
// the write lock, exactly like the engine's dry run always behaved.
public struct DryRunOpsTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        perform(connection)
    }

    // MARK: - Internal
    // Sync body — also the direct surface for synchronous unit tests.
    func perform(_ connection: Connection) -> Result {
        guard let payload = OpsEngine.decodePayload(parameter.payloadJSON) else {
            return OpsEngine.DryRunResult(
                status: "rejected",
                opCount: nil,
                error: "payload must be a JSON object",
                rejectedIndex: nil
            )
        }

        return OpsEngine.dryRun(connection, payload, ruleset: parameter.ruleset)
    }

    // MARK: - Private
}

public extension DryRunOpsTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let payloadJSON: String
        public let ruleset: String?

        // MARK: - Initializer
        public init(payloadJSON: String, ruleset: String? = nil) {
            self.payloadJSON = payloadJSON
            self.ruleset = ruleset
        }
    }

    typealias Result = OpsEngine.DryRunResult
}
