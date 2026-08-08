//
//  NeighborsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct NeighborsTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.neighbors(connection, id: parameter.id, k: parameter.k, cliSessionId: parameter.cliSessionId)
    }
}

public extension NeighborsTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let id: String
        public let k: Int
        public let cliSessionId: String

        // MARK: - Initializer
        public init(id: String, k: Int, cliSessionId: String = "") {
            self.id = id
            self.k = k
            self.cliSessionId = cliSessionId
        }
    }

    typealias Result = (scores: [Candidates.NeighborScore], record: RecordRetrievalTransaction.Parameter?)
}
