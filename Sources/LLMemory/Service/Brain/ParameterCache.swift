//
//  ParameterCache.swift
//  LLMemory
//
//  Created by JSilver on 8/16/26.
//

import Foundation

// One brain's warmed copy of committed parameter state. A box rather than a
// field on Config and Genes because those two are handed around as values —
// a Genes borrowed for a shadow replay has to read the same warmed genome as
// the one it was derived from, not a copy that stopped following it.
//
// The lock is what makes @unchecked Sendable on the holders true rather than
// asserted. Reads are not serialised by anything above: the write scope has a
// gate, the read scope has none, and a Dictionary read against a concurrent
// write is not a stale value but a corrupted one.
final class ParameterCache: @unchecked Sendable {
    // MARK: - Property
    private let lock = NSLock()

    private var config: [String: String] = [:]
    private var genes: [String: Double] = [:]

    // MARK: - Initializer
    // MARK: - Public
    func configValue(_ key: String) -> String? {
        lock.lock()

        defer { lock.unlock() }

        return config[key]
    }

    func geneValue(_ id: String) -> Double? {
        lock.lock()

        defer { lock.unlock() }

        return genes[id]
    }

    // Both halves land together because they were read together — a caller
    // that saw the new config rows and the old genome values would be reading
    // a state the database never held.
    func warm(config: [String: String], genes: [String: Double]) {
        lock.lock()

        defer { lock.unlock() }

        self.config = config
        self.genes = genes
    }

    // Plants a value the database does not hold, so a test can prove a reader
    // consults the row rather than this cache.
    func plantConfigValue(_ key: String, _ value: String) {
        lock.lock()

        defer { lock.unlock() }

        config[key] = value
    }

    // MARK: - Private
}
