//
//  Config.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

enum Config {
    // MARK: - Property
    static let prefix = "config."
    
    private static let nilSentinel = "\u{0}__NIL__"
    
    // The cache lives on the bound brain's context — resolution follows
    // whichever brain's scope is executing.
    private static var cache: [String: String] {
        get { BrainContext.resolved.configCache }
        set { BrainContext.resolved.configCache = newValue }
    }
    private static var warmed: Bool {
        get { BrainContext.resolved.configWarmed }
        set { BrainContext.resolved.configWarmed = newValue }
    }
    
    // MARK: - Initializer
    // MARK: - Public
    static func getInt(_ key: String, default defaultValue: Int) -> Int {
        guard let raw = fetch(key) else { return defaultValue }
        
        return Int(raw) ?? defaultValue
    }
    
    static func getDouble(_ key: String, default defaultValue: Double) -> Double {
        guard let raw = fetch(key) else { return defaultValue }
        
        return Double(raw) ?? defaultValue
    }
    
    static func getString(_ key: String, default defaultValue: String) -> String {
        fetch(key) ?? defaultValue
    }
    
    static func getBool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let raw = fetch(key) else { return defaultValue }
        
        return ["1", "true", "yes"].contains(raw.lowercased())
    }
    
    static func invalidateCache() {
        cache.removeAll()
        warmed = false
        Genes.invalidateCache()
    }

    // The binding norm: cache APIs reachable from outside a scope take the
    // storage and bind its context themselves; the ambient variants above
    // assume an already-bound scope.
    static func invalidateCache(_ storage: GRDBStorage) {
        storage.context.bind { invalidateCache() }
    }
    
    // Re-read the caches from committed state. Run at boot and at the end of
    // every write scope, which is what keeps "the process holds what the
    // database holds" true rather than aspirational.
    //
    // Swap-only: a failed read leaves the existing values in place. Nothing
    // writes these caches inside a transaction, so they can only be behind
    // committed state, never ahead of it — an unreadable database is a reason
    // to keep the last committed values, not to drop to defaults.
    static func reloadCommitted(_ storage: GRDBStorage) {
        storage.context.bind { try? loadCommitted(storage) }
    }

    static func getStringTx(
        _ key: String,
        default defaultValue: String,
        txDB db: Database
    ) -> String {
        let value = try? MetaRecord.fetchOne(db, key: prefix + key)?.value

        return (value ?? nil) ?? defaultValue
    }

    static func set(_ key: String, value: Any, txDB db: Database) throws {
        let stringValue = "\(value)"

        try MetaRecord(key: prefix + key, value: stringValue).upsert(db)

        cache[prefix + key] = stringValue
    }
    
    static func cacheOverrideForTesting(_ key: String, value: String) {
        cache[prefix + key] = value
    }
    
    static func allKeys() -> [String: String] {
        var values: [String: String] = [:]
        
        for (key, value) in cache where value != nilSentinel {
            values[String(key.dropFirst(prefix.count))] = value
        }
        
        return values
    }
    
    // MARK: - Private
    // One snapshot for both caches — config rows and genome values come from
    // the same read transaction, then swap in together.
    private static func loadCommitted(_ storage: GRDBStorage) throws {
        let queue = try storage.connect()
        let (rows, genomeValues) = try queue.read { db in
            (
                try MetaRecord
                    .filter(Column("key").like("\(prefix)%"))
                    .fetchAll(db),
                try FetchGenomeValuesTransaction().perform(db)
            )
        }
        var fresh: [String: String] = [:]

        for row in rows {
            fresh[row.key] = row.value ?? nilSentinel
        }

        cache = fresh
        warmed = true

        Genes.warm(genomeValues)
    }

    private static func fetch(_ key: String) -> String? {
        // Cache-only: the Session that owns this home warms the cache at construction.
        guard let value = cache[prefix + key] else { return nil }
        
        return value == nilSentinel ? nil : value
    }
}
