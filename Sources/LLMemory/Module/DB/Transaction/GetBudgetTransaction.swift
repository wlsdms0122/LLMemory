//
//  GetBudgetTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct GetBudgetTransaction: GRDBTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.getBudget(connection, id: parameter.id, budget: parameter.budget)
    }
}

public extension GetBudgetTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let id: String
        public let budget: Int

        // MARK: - Initializer
        public init(id: String, budget: Int) {
            self.id = id
            self.budget = budget
        }
    }

    typealias Result = (note: Reads.GetNote, record: RecordRetrievalTransaction.Parameter?, cut: Reads.BudgetCut)
}
