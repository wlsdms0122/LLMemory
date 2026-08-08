//
//  ReindexNotesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ReindexNotesTransaction: GRDBWriteTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Index.reindexLocked(filePaths: parameter.filePaths)
    }
}

public extension ReindexNotesTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let filePaths: [String]

        // MARK: - Initializer
        public init(filePaths: [String]) {
            self.filePaths = filePaths
        }
    }

    typealias Result = Int
}
