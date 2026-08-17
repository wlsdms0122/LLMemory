//
//  StatsService.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation

// Stats-domain service — pure observation of the corpus and its activation
// traces.
public struct StatsService: StatsServiceable {
    // MARK: - Property
    let storage: any GRDBStorable

    // MARK: - Initializer
    init(storage: any GRDBStorable) {
        self.storage = storage
    }

    // MARK: - Public
    public func noteStats(
        id: String
    ) async throws -> NoteStats? {
        try await storage.run(NoteStatsTransaction(id: id))
    }

    public func prefixStats(
        prefix: String
    ) async throws -> PrefixStats {
        try await storage.run(PrefixStatsTransaction(prefix: prefix))
    }

    public func overallStats() async throws -> OverallStats {
        try await storage.run(OverallStatsTransaction())
    }

    // MARK: - Private
}
