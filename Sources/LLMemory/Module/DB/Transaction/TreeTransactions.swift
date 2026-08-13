//
//  TreeTransactions.swift
//  LLMemory
//
//  Created by JSilver on 8/13/26.
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

// The hierarchy is not stored — it is read off the ids, one level at a time.
// Grouping happens here rather than in SQL because the shape (split on dots,
// take the next label) is the id syntax itself, and the id syntax is Swift's
// to know; a corpus this size makes the choice free.
struct FetchTreeTransaction: GRDBReadTransaction {
    // MARK: - Property
    let prefix: String?

    // MARK: - Initializer
    init(prefix: String? = nil) {
        self.prefix = prefix
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [TreeRow] {
        let all = try String.fetchAll(db, sql: "SELECT id FROM notes")
        let ids = prefix.map { value in all.filter { id in id.hasPrefix(value + ".") } } ?? all
        let depth = prefix.map { value in value.split(separator: ".").count } ?? 0
        var counts: [String: Int] = [:]

        for id in ids {
            let labels = id.split(separator: ".").map(String.init)

            guard labels.count > depth else { continue }

            counts[labels.prefix(depth + 1).joined(separator: "."), default: 0] += 1
        }

        return counts.keys.sorted().map { key in TreeRow(prefix: key, notes: counts[key] ?? 0) }
    }

    // MARK: - Private
}
