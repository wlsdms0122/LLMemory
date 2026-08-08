//
//  NoteMetaByKVTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct NoteMetaByKVTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.metaByKV(connection, namespace: parameter.namespace, key: parameter.key, value: parameter.value, limit: parameter.limit)
    }
}

public extension NoteMetaByKVTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let namespace: String
        public let key: String
        public let value: String?
        public let limit: Int

        // MARK: - Initializer
        public init(namespace: String, key: String, value: String?, limit: Int) {
            self.namespace = namespace
            self.key = key
            self.value = value
            self.limit = limit
        }
    }

    typealias Result = [(noteId: String, value: String)]
}
