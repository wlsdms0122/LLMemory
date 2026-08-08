//
//  RelatedNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct RelatedNotesTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.related(connection, text: parameter.text, kind: parameter.kind, cliSessionId: parameter.cliSessionId, includeBodies: parameter.includeBodies)
    }
}

public extension RelatedNotesTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let text: String
        public let kind: String?
        public let cliSessionId: String
        public let includeBodies: Bool

        // MARK: - Initializer
        public init(text: String, kind: String?, cliSessionId: String, includeBodies: Bool) {
            self.text = text
            self.kind = kind
            self.cliSessionId = cliSessionId
            self.includeBodies = includeBodies
        }
    }

    typealias Result = (result: Framing.RelatedResult, record: RecordRetrievalTransaction.Parameter)
}
