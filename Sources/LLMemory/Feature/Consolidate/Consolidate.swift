//
//  Consolidate.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public struct Consolidate {
    let session: Session
    
    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }
    
    public func integrate() async throws -> Consolidation.IntegrateResult {
        try await ConsolidateService.integrate(session.storage)
    }

    public func homeostasis() async throws -> ConsolidateService.HomeostasisReport {
        try await ConsolidateService.homeostasis(session.storage)
    }

    public func prune() async throws -> Consolidation.PruneResult {
        try await ConsolidateService.prune(session.storage)
    }

    public func report() async throws -> (axis: Consolidation.AxisReport, tag: Consolidation.TagReport) {
        try await ConsolidateService.report(session.storage)
    }

}
