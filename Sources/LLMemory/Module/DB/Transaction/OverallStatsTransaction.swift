//
//  OverallStatsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct OverallStatsTransaction: GRDBTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.overallStats(connection)
    }
}

public extension OverallStatsTransaction {
    typealias Parameter = Void
    typealias Result = Stats.OverallStats
}
