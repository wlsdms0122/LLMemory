//
//  ValidateTermsTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct ValidateTermsTransaction: LegacyWriteTransaction {
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
        try connection.write { db -> Result in
            let pass = try ValidatePendingTermsTransaction(noteIds: nil).perform(db)
            let staleRejected = parameter.rejectStale ? try RejectStalePendingTermsTransaction().perform(db) : 0

            return Indexer.ValidateResult(
                activated: pass.activated,
                rejected: pass.rejected,
                stillPending: pass.stillPending,
                staleRejected: staleRejected,
                rejectBreakdown: pass.rejectBreakdown
            )
        }
    }
}

public extension ValidateTermsTransaction {
    struct Parameter: Sendable {
        // MARK: - Property
        public let rejectStale: Bool

        // MARK: - Initializer
        public init(rejectStale: Bool) {
            self.rejectStale = rejectStale
        }
    }

    typealias Result = Indexer.ValidateResult
}
