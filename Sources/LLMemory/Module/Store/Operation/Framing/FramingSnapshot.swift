//
//  FramingSnapshot.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct FramingSnapshot: Sendable {
    // MARK: - Property
    public var keywords: [String]
    public var similar: [SimilarNote]
    public var linked: [ExpandedNote]
    public var vectorLinked: [VectorHit]
    public var topTags: [(String, Int)]
    public var cooccur: [(String, String, Int)]
    public var vocab: [String]
    public var entityHints: [String]
    public var entityHits: [EntityHit]
    public var degraded: [String] = []

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
