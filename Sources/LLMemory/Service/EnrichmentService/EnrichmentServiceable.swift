//
//  EnrichmentServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// The semantic layer's own observation surface — term validation state,
// association edges, vector coverage, and per-provenance noise rates.
protocol EnrichmentServiceable: Sendable {
    func status() async throws -> EnrichmentStatus
}
