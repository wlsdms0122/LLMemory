//
//  Consolidate.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB
import Storage

public struct Consolidate {
    let session: Session
    
    // MARK: - Initializer
    init(session: Session) {
        self.session = session
    }
    
    public func integrate() async throws -> Consolidation.IntegrateResult {
        try await session.storage.run(IntegrateTransaction())
    }

    public func homeostasis() async throws -> Homeostasis.Report {
        try await session.storage.run(HomeostasisTransaction())
    }

    public func prune() async throws -> Consolidation.PruneResult {
        try await session.storage.run(PruneTransaction())
    }

    public func report() async throws -> (axis: Consolidation.AxisReport, tag: Consolidation.TagReport) {
        try await session.storage.run(ConsolidateReportTransaction())
    }

}
