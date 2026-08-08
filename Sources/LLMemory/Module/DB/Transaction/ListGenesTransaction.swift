//
//  ListGenesTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ListGenesTransaction: GRDBTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        Genome.list()
    }
}

public extension ListGenesTransaction {
    typealias Parameter = Void
    typealias Result = [Genome.ListRow]
}
