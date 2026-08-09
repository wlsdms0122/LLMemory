//
//  AxisStatsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct AxisStatsTransaction: LegacyReadTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.axisStats(connection, axis: parameter.axis)
    }
}

public extension AxisStatsTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let axis: String

        // MARK: - Initializer
        public init(axis: String) {
            self.axis = axis
        }
    }

    typealias Result = Stats.AxisStats
}
