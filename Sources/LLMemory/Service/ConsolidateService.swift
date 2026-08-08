//
//  ConsolidateService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Consolidation-domain service — the periodic hygiene passes.
public enum ConsolidateService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func integrate(_ storage: GRDBStorage) async throws -> Consolidation.IntegrateResult {
        try await storage.run(IntegrateTransaction())
    }

    public static func homeostasis(_ storage: GRDBStorage) async throws -> Homeostasis.Report {
        try await storage.run(HomeostasisTransaction())
    }

    public static func prune(_ storage: GRDBStorage) async throws -> Consolidation.PruneResult {
        try await storage.run(PruneTransaction())
    }

    public static func report(
        _ storage: GRDBStorage
    ) async throws -> (axis: Consolidation.AxisReport, tag: Consolidation.TagReport) {
        try await storage.run(ConsolidateReportTransaction())
    }

    // MARK: - Private
}
