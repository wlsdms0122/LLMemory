//
//  FetchTreeTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

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
        let ids = prefix.map { value in all.filter { id in Paths.id(id, isWithin: value) } } ?? all
        let depth = prefix.map { value in Paths.labels(of: value).count } ?? 0
        var counts: [String: Int] = [:]

        // A note sitting exactly at the prefix gets its own row rather than being
        // dropped: the rows are how a branch's total breaks down, and a total
        // that its own breakdown cannot reach is a number nobody can check.
        for id in ids {
            guard let branch = Paths.branch(of: id, depth: depth + 1) ?? prefix else { continue }

            counts[branch, default: 0] += 1
        }

        return counts.keys.sorted().map { key in TreeRow(prefix: key, notes: counts[key] ?? 0) }
    }

    // MARK: - Private
}
