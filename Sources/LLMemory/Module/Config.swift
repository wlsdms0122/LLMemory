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
    
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    nonisolated(unsafe) private static var warmed = false
    
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
        Genome.invalidateCache()
    }
    
    static func warmCache(_ storage: GRDBStorage) {
        do {
            let queue = try storage.connect()
            let rows = try queue.read { db in
                try Row.fetchAll(
                    db,
                    sql: "SELECT key, value FROM meta WHERE key LIKE ?",
                    arguments: [prefix + "%"]
                )
            }
            
            cache.removeAll()
            
            for row in rows {
                let key: String = row["key"]
                cache[key] = (row["value"] as String?) ?? nilSentinel
            }
            
            warmed = true
            Genome.warmCache(queue)
        } catch { }
    }
    
    static func set(_ queue: any DatabaseWriter, _ key: String, value: Any) {
        let stringValue = "\(value)"
        
        do {
            try queue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO meta (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                    arguments: [prefix + key, stringValue]
                )
            }
            
            cache[prefix + key] = stringValue
        } catch { }
    }
    
    static func getStringTx(
        _ key: String,
        default defaultValue: String,
        txDB db: Database
    ) -> String {
        let value = try? String.fetchOne(
            db,
            sql: "SELECT value FROM meta WHERE key = ?",
            arguments: [prefix + key]
        )
        
        return value ?? defaultValue
    }
    
    static func set(_ key: String, value: Any, txDB db: Database) throws {
        let stringValue = "\(value)"
        
        try db.execute(
            sql: """
            INSERT INTO meta (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            arguments: [prefix + key, stringValue]
        )
        
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
    private static func fetch(_ key: String) -> String? {
        // Cache-only: the Session that owns this home warms the cache at construction.
        guard let value = cache[prefix + key] else { return nil }
        
        return value == nilSentinel ? nil : value
    }
}
