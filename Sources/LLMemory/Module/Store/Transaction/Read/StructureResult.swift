//
//  StructureResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

public struct StructureResult: Sendable {
    // MARK: - Property
    public let tree: [TreeRow]
    public let distribution: LinkDistribution
    public let prefixStats: PrefixStats?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
