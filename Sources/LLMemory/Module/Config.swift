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
    
    // Re-read the caches from committed state. Run at boot and at the end of
    // every write scope, which is what keeps "the process holds what the
    // database holds" true rather than aspirational.
    //
    // Swap-only: a failed read leaves the existing values in place. Nothing
    // writes these caches inside a transaction, so they can only be behind
    // committed state, never ahead of it — an unreadable database is a reason
    // to keep the last committed values, not to drop to defaults.
    //
    // The three failures below are how a brain answers before it exists: a
    // Session is constructed against a directory the migration has not reached
    // yet, and bootstrap re-runs this once it has. Every other failure means a
    // database that was readable a moment ago no longer is, and the process is
    // about to serve values it can no longer justify — so it says so.
    static func reloadCommitted(_ storage: GRDBStorage) {
        storage.context.bind {
            do {
                try loadCommitted(storage)
            } catch DBError.notInitialized, DBError.pendingMigrations, DBError.superseded {
                return
            } catch {
                FileHandle.standardError.write(
                    Data("llmemory: parameter cache is stale — reload failed: \(error)\n".utf8)
                )
            }
        }
    }

    static func getStringTx(
        _ key: String,
        default defaultValue: String,
        txDB db: Database
    ) -> String {
        let value = try? MetaRecord.fetchOne(db, key: prefix + key)?.value

        return (value ?? nil) ?? defaultValue
    }

    // Writes the row and only the row. A caller that must read a value it is
    // itself writing reads the row too (getStringTx) — the cache catches up
    // when the scope commits.
    static func set(_ key: String, value: Any, txDB db: Database) throws {
        try MetaRecord(key: prefix + key, value: "\(value)").upsert(db)
    }
    
    // The two seams below exist so a fixture can act on one named brain. Both
    // run outside any scope, where the ambient context is a weak fallback —
    // whichever Session is still alive — so the brain is an argument, not
    // something they go looking for.

    // Drops both caches so one fixture's values cannot outlive its brain.
    // Nothing on the live path clears a cache: a cache that follows committed
    // state is replaced by the next load, never emptied in between.
    static func discardCache(_ context: BrainContext) {
        context.bind {
            cache.removeAll()
            Genes.invalidateCache()
        }
    }

    // Plants a value the database does not hold, so a test can prove a reader
    // consults the row rather than this cache.
    static func plantStaleCacheValue(_ context: BrainContext, _ key: String, value: String) {
        context.bind { cache[prefix + key] = value }
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

        Genes.warm(genomeValues)
    }

    private static func fetch(_ key: String) -> String? {
        // Cache-only: the Session that owns this home warms the cache at construction.
        guard let value = cache[prefix + key] else { return nil }
        
        return value == nilSentinel ? nil : value
    }
}
