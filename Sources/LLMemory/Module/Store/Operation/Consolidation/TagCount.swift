//
//  TagCount.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

// Consolidation result shapes — reports and summaries the consolidate
// service returns, flat top-level models like the other service results.
public struct TagCount: Encodable, Sendable {
    // MARK: - Property
    public let tag: String
    public let count: Int

    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()

        try container.encode(tag)
        try container.encode(count)
    }

    // MARK: - Private
}
