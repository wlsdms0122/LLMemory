//
//  StatsService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage

// Stats-domain service — pure observation of the corpus and its activation
// traces.
public enum StatsService {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Public
    public static func noteStats(
        _ storage: GRDBStorage,
        id: String
    ) async throws -> NoteStats? {
        try await storage.read { scope in try scope.run(NoteStatsTransaction(id: id)) }
    }

    public static func axisStats(
        _ storage: GRDBStorage,
        axis: String
    ) async throws -> AxisStats {
        try await storage.read { scope in try scope.run(AxisStatsTransaction(axis: axis)) }
    }

    public static func overallStats(_ storage: GRDBStorage) async throws -> OverallStats {
        try await storage.read { scope in try scope.run(OverallStatsTransaction()) }
    }

    // MARK: - Private
}
