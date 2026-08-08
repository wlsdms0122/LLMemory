//
//  IntegrateTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct IntegrateTransaction: GRDBWriteTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        var result = try Consolidate.integrateLocked()
        let integrity = try connection.read { db in try Consolidate.integrityL1(db) }
        result.integrityL1 = Consolidate.IntegrateResult.IntegrityReport(
            checked: integrity.checked,
            issues: integrity.issues
        )
        result.summary.integrityL1Issues = integrity.issues.count

        return result
    }
}

public extension IntegrateTransaction {
    typealias Parameter = Void
    typealias Result = Consolidate.IntegrateResult
}
