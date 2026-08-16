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
public struct EnrichmentService: EnrichmentServiceable {
    // MARK: - Property
    let storage: GRDBStorage
    let brain: BrainContext

    // MARK: - Initializer
    init(storage: GRDBStorage, brain: BrainContext) {
        self.storage = storage
        self.brain = brain
    }

    // MARK: - Public
    public func status() async throws -> EnrichmentStatus {
        try await storage.read { scope in try scope.run(
                EnrichmentStatusTransaction(
                    neighborFloor: brain.genes.double("links.neighbor_floor"),
                    enrichment: EnrichmentTuning(brain.config)
                )
            )
        }
    }

    // MARK: - Private
}
