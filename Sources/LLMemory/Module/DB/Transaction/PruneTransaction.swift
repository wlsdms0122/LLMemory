//
//  PruneTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct PruneTransaction: GRDBWriteTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Consolidate.pruneLocked(connection)
    }
}

public extension PruneTransaction {
    typealias Parameter = Void
    typealias Result = Consolidate.PruneResult
}
