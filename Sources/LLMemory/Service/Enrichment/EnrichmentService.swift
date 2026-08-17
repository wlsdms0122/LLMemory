//
//  EnrichmentService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// Enrichment-domain service — observation of the semantic layer (terms,
// assoc edges, vectors, provenance noise).
public struct EnrichmentService: EnrichmentServiceable {
    // MARK: - Property
    let storage: any GRDBStorable
    let brain: BrainContext

    // The enrichment keys and defaults have one owner; this resolves them
    // from this brain each time they are needed.
    private var enrichment: EnrichmentTuning { EnrichmentTuning(brain.config) }

    // MARK: - Initializer
    init(storage: any GRDBStorable, brain: BrainContext) {
        self.storage = storage
        self.brain = brain
    }

    // MARK: - Public
    public func status() async throws -> EnrichmentStatus {
        try await storage.run(
            EnrichmentStatusTransaction(
                neighborFloor: brain.genes.double("links.neighbor_floor"),
                disagreeFloor: enrichment.disagreeFloor,
                modelAlarmRate: enrichment.modelAlarmRate
            )
        )
    }

    // MARK: - Private
}
