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
public struct StatsService: StatsServiceable {
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

    public func prefixStats(
        prefix: String
    ) async throws -> PrefixStats {
        try await storage.read { scope in try scope.run(PrefixStatsTransaction(prefix: prefix)) }
    }

    public func overallStats() async throws -> OverallStats {
        try await storage.read { scope in try scope.run(OverallStatsTransaction()) }
    }

    // MARK: - Private
}
