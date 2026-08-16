//
//  Config.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// One brain's configuration, read out of the warmed parameter cache. A value
// rather than a namespace because the answers belong to a brain: two live
// brains in one process have two of these, and nothing has to agree about
// which is current.
//
// It reads the cache and nothing else. The rows behind the cache are the
// store's — a config transaction reaches them — and what this type owns of
// them is the key encoding both sides spell.
struct Config: Sendable {
    // MARK: - Property
    static let prefix = "config."

    static let nilSentinel = "\u{0}__NIL__"

    private let cache: ParameterCache

    // MARK: - Initializer
    init(cache: ParameterCache) {
        self.cache = cache
    }

    // MARK: - Public
    func getInt(_ key: String, default defaultValue: Int) -> Int {
        guard let raw = fetch(key) else { return defaultValue }

        return Int(raw) ?? defaultValue
    }

    func getDouble(_ key: String, default defaultValue: Double) -> Double {
        guard let raw = fetch(key) else { return defaultValue }

        return Double(raw) ?? defaultValue
    }

    func getString(_ key: String, default defaultValue: String) -> String {
        fetch(key) ?? defaultValue
    }

    func getBool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let raw = fetch(key) else { return defaultValue }

        return ["1", "true", "yes"].contains(raw.lowercased())
    }

    // MARK: - Private
    private func fetch(_ key: String) -> String? {
        // Cache-only: the Session that owns this home warms it at construction
        // and again at the end of every write scope.
        guard let value = cache.configValue(Self.prefix + key) else { return nil }

        return value == Self.nilSentinel ? nil : value
    }
}
