//
//  SearchNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct SearchNotesTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.search(connection, query: parameter.query, axis: parameter.axis, limit: parameter.limit, expand: parameter.expand, cliSessionId: parameter.cliSessionId, includeStale: parameter.includeStale, excludeAxes: parameter.excludeAxes, raw: parameter.raw)
    }
}

public extension SearchNotesTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let query: String
        public let axis: String?
        public let limit: Int
        public let expand: Int
        public let cliSessionId: String
        public let includeStale: Bool
        public let excludeAxes: [String]
        public let raw: Bool

        // MARK: - Initializer
        public init(query: String, axis: String?, limit: Int, expand: Int, cliSessionId: String, includeStale: Bool, excludeAxes: [String], raw: Bool) {
            self.query = query
            self.axis = axis
            self.limit = limit
            self.expand = expand
            self.cliSessionId = cliSessionId
            self.includeStale = includeStale
            self.excludeAxes = excludeAxes
            self.raw = raw
        }
    }

    typealias Result = (rows: [Search.SearchRow], extra: [Links.ExpandedNote], record: RecordRetrievalTransaction.Parameter)
}
