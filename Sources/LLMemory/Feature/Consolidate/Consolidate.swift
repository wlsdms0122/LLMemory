//
//  Consolidate.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Consolidate {
    // MARK: - Property
    let service: any ConsolidateServiceable

    // MARK: - Initializer
    init(service: any ConsolidateServiceable) {
        self.service = service
    }
    
    public func integrate() async throws -> IntegrateResult {
        try await service.integrate()
    }

    public func homeostasis() async throws -> HomeostasisReport {
        try await service.homeostasis()
    }

    public func prune() async throws -> PruneResult {
        try await service.prune()
    }

    public func report() async throws -> ConsolidateTagReport {
        try await service.report()
    }

}
