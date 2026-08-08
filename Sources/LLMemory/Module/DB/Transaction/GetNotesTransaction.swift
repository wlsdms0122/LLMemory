//
//  GetNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct GetNotesTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try QueryFeature.get(ids: parameter.ids, cliSessionId: parameter.cliSessionId)
    }
}

public extension GetNotesTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let ids: [String]
        public let cliSessionId: String

        // MARK: - Initializer
        public init(ids: [String], cliSessionId: String = "") {
            self.ids = ids
            self.cliSessionId = cliSessionId
        }
    }

    typealias Result = (found: [QueryFeature.GetNote], missing: [String])
}
