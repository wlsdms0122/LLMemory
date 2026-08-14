//
//  StatsServiceable.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Pure observation over the catalog — counts and distributions, per note,
// per id prefix, and corpus-wide.
protocol StatsServiceable: Sendable {
    func noteStats(id: String) async throws -> NoteStats?

    func prefixStats(prefix: String) async throws -> PrefixStats

    func overallStats() async throws -> OverallStats
}
