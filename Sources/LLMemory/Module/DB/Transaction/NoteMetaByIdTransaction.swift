//
//  NoteMetaByIdTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct NoteMetaByIdTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.metaById(connection, noteId: parameter.noteId, namespace: parameter.namespace)
    }
}

public extension NoteMetaByIdTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let noteId: String
        public let namespace: String?

        // MARK: - Initializer
        public init(noteId: String, namespace: String?) {
            self.noteId = noteId
            self.namespace = namespace
        }
    }

    typealias Result = [String: [String: String]]
}
