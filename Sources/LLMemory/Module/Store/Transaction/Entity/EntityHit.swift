//
//  EntityHit.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// entity_index transactions — the per-note entity registry and its
// freshness-gated lookup.
public struct EntityHit: Sendable {
    // MARK: - Property
    public let entity: String
    public let noteId: String
    public let lastSeenAt: Int
    public let hitCount: Int
    public let title: String?
    public let summary: String?

    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
