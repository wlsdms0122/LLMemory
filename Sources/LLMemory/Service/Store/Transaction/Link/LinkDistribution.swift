//
//  LinkDistribution.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// The link-graph vocabulary — edge kinds, their direction/lifecycle
// classes, and the note_links transactions.
public struct LinkDistribution: Sendable {
    // MARK: - Property
    public let byKind: [(kind: String, count: Int, min: Double, avg: Double, max: Double)]
    public let weightBuckets: [String: Int]
    public let topDegree: [(id: String, title: String, degree: Int)]

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
