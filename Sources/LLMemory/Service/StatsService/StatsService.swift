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
public struct StatsService: Sendable {
    // MARK: - Property
    let storage: GRDBStorage

    // MARK: - Initializer
    init(storage: GRDBStorage) {
        self.storage = storage
    }

    // MARK: - Public
    public func noteStats(
        id: String
    ) async throws -> NoteStats? {
        try await storage.read { scope in try scope.run(NoteStatsTransaction(id: id)) }
    }

    public func axisStats(
        axis: String
    ) async throws -> AxisStats {
        try await storage.read { scope in try scope.run(AxisStatsTransaction(axis: axis)) }
    }

    public func overallStats() async throws -> OverallStats {
        try await storage.read { scope in try scope.run(OverallStatsTransaction()) }
    }

    // MARK: - Private
}
