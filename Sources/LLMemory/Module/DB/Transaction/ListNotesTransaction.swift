//
//  ListNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ListNotesTransaction: LegacyReadTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.list(connection, priority: parameter.priority, axis: parameter.axis, stale: parameter.stale, sourceStale: parameter.sourceStale, limit: parameter.limit)
    }
}

public extension ListNotesTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let priority: String?
        public let axis: String?
        public let stale: Bool
        public let sourceStale: Bool
        public let limit: Int?

        // MARK: - Initializer
        public init(priority: String?, axis: String?, stale: Bool, sourceStale: Bool, limit: Int?) {
            self.priority = priority
            self.axis = axis
            self.stale = stale
            self.sourceStale = sourceStale
            self.limit = limit
        }
    }

    typealias Result = [Reads.ListRow]
}
