//
//  VerifySourcesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct VerifySourcesTransaction: GRDBWriteTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        try connection.write { db in try NoteSources.bulkVerify(db) }
    }
}

public extension VerifySourcesTransaction {
    typealias Parameter = Void
    typealias Result = NoteSources.BulkVerifyResult
}
