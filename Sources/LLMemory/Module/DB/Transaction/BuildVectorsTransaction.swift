//
//  BuildVectorsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct BuildVectorsTransaction: GRDBWriteTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Vectors.build(connection)
    }
}

public extension BuildVectorsTransaction {
    typealias Parameter = Void
    typealias Result = Vectors.BuildResult
}
