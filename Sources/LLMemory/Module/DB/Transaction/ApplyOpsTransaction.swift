//
//  ApplyOpsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage
import GRDB

// The atomic write vocabulary — one ops payload applied by the engine under
// the cross-process write lock `run` provides. The payload crosses the
// transaction boundary as a JSON string; the engine's [String: Any] world
// stays inside the DB module.
public struct ApplyOpsTransaction: LegacyWriteTransaction {
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
            return OpsEngine.Result(
                status: "rejected",
                opResults: [],
                error: "payload must be a JSON object",
                rejectedIndex: nil,
                rationale: "",
                recoveryFailed: []
            )
        }

        return OpsEngine.apply(
            connection,
            payload,
            sessionId: parameter.sessionId,
            ruleset: parameter.ruleset
        )
    }

    // MARK: - Private
}

public extension ApplyOpsTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let payloadJSON: String
        public let sessionId: String?
        public let ruleset: String?

        // MARK: - Initializer
        public init(payloadJSON: String, sessionId: String? = nil, ruleset: String? = nil) {
            self.payloadJSON = payloadJSON
            self.sessionId = sessionId
            self.ruleset = ruleset
        }
    }

    typealias Result = OpsEngine.Result
}
