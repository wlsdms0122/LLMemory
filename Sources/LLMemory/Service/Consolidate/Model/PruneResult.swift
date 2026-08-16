//
//  PruneResult.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

public struct PruneResult: Encodable, Sendable {
    public enum CodingKeys: String, CodingKey {
        case linksDecayed = "links_decayed"
        case linksPruned = "links_pruned"
    }

    // MARK: - Property
    public let linksDecayed: Int
    public let linksPruned: Int

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
