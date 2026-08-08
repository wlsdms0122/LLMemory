//
//  EntityNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct EntityNotesTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try QueryFeature.entity(connection, name: parameter.name, limit: parameter.limit)
    }
}

public extension EntityNotesTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let name: String?
        public let limit: Int

        // MARK: - Initializer
        public init(name: String?, limit: Int) {
            self.name = name
            self.limit = limit
        }
    }

    typealias Result = [Reads.EntityHit]
}
