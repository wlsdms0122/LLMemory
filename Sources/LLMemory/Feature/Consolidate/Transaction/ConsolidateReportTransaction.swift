//
//  ConsolidateReportTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ConsolidateReportTransaction: GRDBTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        try connection.read { db in
            (try Consolidate.axisReport(db), try Consolidate.tagReport(db))
        }
    }
}

public extension ConsolidateReportTransaction {
    typealias Parameter = Void
    typealias Result = (axis: Consolidate.AxisReport, tag: Consolidate.TagReport)
}
