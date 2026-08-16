//
//  Config.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

// One brain's configuration rows, warmed into memory. An instance rather than
// a namespace because the values belong to a brain: two live brains in one
// process have two of these, and nothing has to agree about which is current.
final class Config: @unchecked Sendable {
    // MARK: - Property
    static let prefix = "config."

    private static let nilSentinel = "\u{0}__NIL__"

    private var cache: [String: String] = [:]

    // MARK: - Initializer
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
    func reloadCommitted(_ storage: GRDBStorage, genes: Genes) {
        do {
            try loadCommitted(storage, genes: genes)
        } catch DBError.notInitialized, DBError.pendingMigrations, DBError.superseded {
            return
        } catch {
            FileHandle.standardError.write(
                Data("llmemory: parameter cache is stale — reload failed: \(error)\n".utf8)
            )
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

    // Plants a value the database does not hold, so a test can prove a reader
    // consults the row rather than this cache.
    func plantStaleCacheValue(_ key: String, value: String) {
        cache[Self.prefix + key] = value
    }

    // MARK: - Private
    // One snapshot for both caches — config rows and genome values come from
    // the same read transaction, then swap in together.
    private func loadCommitted(_ storage: GRDBStorage, genes: Genes) throws {
        let queue = try storage.connect()
        let (rows, genomeValues) = try queue.read { db in
            (
                try MetaRecord
                    .filter(Column("key").like("\(Self.prefix)%"))
                    .fetchAll(db),
                try FetchGenomeValuesTransaction().perform(db)
            )
        }
        var fresh: [String: String] = [:]

        for row in rows {
            fresh[row.key] = row.value ?? Self.nilSentinel
        }

        cache = fresh

        genes.warm(genomeValues)
    }

    private func fetch(_ key: String) -> String? {
        // Cache-only: the Session that owns this home warms the cache at
        // construction.
        guard let value = cache[Self.prefix + key] else { return nil }

        return value == Self.nilSentinel ? nil : value
    }
}
