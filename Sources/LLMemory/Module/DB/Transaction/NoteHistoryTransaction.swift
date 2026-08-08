//
//  NoteHistoryTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct NoteHistoryTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.history(connection, noteId: parameter.noteId, limit: parameter.limit)
    }
}

public extension NoteHistoryTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let noteId: String
        public let limit: Int

        // MARK: - Initializer
        public init(noteId: String, limit: Int) {
            self.noteId = noteId
            self.limit = limit
        }
    }

    typealias Result = [Reads.HistoryEvent]
}
