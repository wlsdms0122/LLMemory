//
//  GeneHistoryTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct GeneHistoryTransaction: LegacyReadTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        try connection.read { db in
            try Genome.history(db, geneId: parameter.gene, limit: parameter.limit)
        }
    }
}

public extension GeneHistoryTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let gene: String?
        public let limit: Int

        // MARK: - Initializer
        public init(gene: String?, limit: Int) {
            self.gene = gene
            self.limit = limit
        }
    }

    typealias Result = [Genome.HistoryRow]
}
