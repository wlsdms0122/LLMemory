//
//  EnrichmentStatusTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct EnrichmentStatusTransaction: GRDBTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try Retrieval.enrichment(connection)
    }
}

public extension EnrichmentStatusTransaction {
    typealias Parameter = Void
    typealias Result = EnrichmentReview.Status
}
