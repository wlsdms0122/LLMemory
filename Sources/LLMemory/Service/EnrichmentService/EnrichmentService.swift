//
//  EnrichmentService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Enrichment-domain service — observation of the semantic layer (terms,
// assoc edges, vectors, provenance noise).
public struct EnrichmentService: Sendable {
    // MARK: - Property
    let storage: GRDBStorage

    // MARK: - Initializer
    init(storage: GRDBStorage) {
        self.storage = storage
    }

    // MARK: - Public
    public func status() async throws -> EnrichmentStatus {
        try await storage.read { scope in try scope.run(EnrichmentStatusTransaction()) }
    }

    // MARK: - Private
}
