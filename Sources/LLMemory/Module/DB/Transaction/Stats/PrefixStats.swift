//
//  PrefixStats.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct PrefixStats: Sendable {
    // MARK: - Property
    public let total: Int
    public let stale: Int
    public let eager: Int
    public let avgWords: Double
    public let maxWords: Int
    public let avgSections: Double
    public let totalHits: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
