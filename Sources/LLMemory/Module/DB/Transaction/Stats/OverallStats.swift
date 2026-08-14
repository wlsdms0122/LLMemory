//
//  OverallStats.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct OverallStats: Sendable {
    // MARK: - Property
    public let total: Int
    public let stale: Int
    public let tree: [TreeRow]
    public let hitNonZero: Int
    public let hitZero: Int
    public let hitAvg: Double
    public let hitMax: Int
    public let avgWords: Double
    public let maxWords: Int
    public let avgSections: Double
    public let activation: ActivationStats

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
