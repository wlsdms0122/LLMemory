//
//  Consolidate.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Consolidate {
    // MARK: - Property
    let consolidate: ConsolidateService

    // MARK: - Initializer
    init(consolidate: ConsolidateService) {
        self.consolidate = consolidate
    }
    
    public func integrate() async throws -> Consolidation.IntegrateResult {
        try await consolidate.integrate()
    }

    public func homeostasis() async throws -> ConsolidateService.HomeostasisReport {
        try await consolidate.homeostasis()
    }

    public func prune() async throws -> Consolidation.PruneResult {
        try await consolidate.prune()
    }

    public func report() async throws -> (axis: Consolidation.AxisReport, tag: Consolidation.TagReport) {
        try await consolidate.report()
    }

}
