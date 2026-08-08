//
//  ListAxesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ListAxesTransaction: GRDBTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try QueryFeature.listAxes()
    }
}

public extension ListAxesTransaction {
    typealias Parameter = Void
    typealias Result = [(axis: String, description: String?, count: Int)]
}
