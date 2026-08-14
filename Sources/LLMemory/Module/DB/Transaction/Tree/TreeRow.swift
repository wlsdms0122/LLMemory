//
//  TreeRow.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// One branch of the address space: a prefix and how many notes live under it.
// Encoded as a compact array ([prefix, notes]) — the same shape every counting
// surface has used.
public struct TreeRow: Encodable, Sendable {
    // MARK: - Property
    public let prefix: String
    public let notes: Int

    // MARK: - Initializer
    // MARK: - Public
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()

        try container.encode(prefix)
        try container.encode(notes)
    }

    // MARK: - Private
}
