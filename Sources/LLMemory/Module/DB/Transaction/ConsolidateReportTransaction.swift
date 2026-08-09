//
//  ConsolidateReportTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ConsolidateReportTransaction: LegacyReadTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        try connection.read { db in
            (try Consolidation.axisReport(db), try Consolidation.tagReport(db))
        }
    }
}

public extension ConsolidateReportTransaction {
    typealias Parameter = Void
    typealias Result = (axis: Consolidation.AxisReport, tag: Consolidation.TagReport)
}
