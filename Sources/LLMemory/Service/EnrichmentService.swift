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
public enum EnrichmentService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func status(_ storage: GRDBStorage) async throws -> EnrichmentStatus {
        try await storage.read { scope in try scope.run(EnrichmentStatusTransaction()) }
    }

    // MARK: - Private
}
