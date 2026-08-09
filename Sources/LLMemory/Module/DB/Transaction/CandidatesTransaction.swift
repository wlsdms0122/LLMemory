//
//  CandidatesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct CandidatesTransaction: LegacyReadTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.candidates(connection, kinds: parameter.kinds, limit: parameter.limit)
    }
}

public extension CandidatesTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let kinds: [String]
        public let limit: Int

        // MARK: - Initializer
        public init(kinds: [String], limit: Int) {
            self.kinds = kinds
            self.limit = limit
        }
    }

    typealias Result = [String: Candidates.Batch]
}
