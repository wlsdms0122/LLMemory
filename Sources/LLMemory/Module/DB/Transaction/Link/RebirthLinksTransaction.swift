//
//  RebirthLinksTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RebirthLinksTransaction: GRDBBrainTransaction {
    // MARK: - Property
    // A factor per note, absent meaning the gene's default — which is not
    // something a constructor can answer, since the brain arrives with the
    // database and not before it.
    let ranked: [(id: String, factor: Double?)]
    let cap: Double

    // MARK: - Initializer
    init(ranked: [(id: String, factor: Double?)], cap: Double = 1.0) {
        self.ranked = ranked
        self.cap = cap
    }

    // An unranked set — every note carries the same weight of evidence.
    init(noteIds: [String], factor: Double? = nil, cap: Double = 1.0) {
        self.init(ranked: noteIds.map { id in (id, factor) }, cap: cap)
    }

    // MARK: - Public
    @discardableResult
    func perform(_ db: Database, _ brain: BrainContext) throws -> Int {
        guard ranked.count >= 2 else { return 0 }

        let defaultFactor = brain.genes.double("rebirth.default_factor")
        var factorOf: [String: Double] = [:]

        for (id, factor) in ranked {
            factorOf[id] = max(factorOf[id] ?? 0, factor ?? defaultFactor)
        }

        let ids = Array(factorOf.keys)
        let now = Int(Date().timeIntervalSince1970)
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        var arguments: [DatabaseValueConvertible?] = []
        arguments.append(contentsOf: ids as [DatabaseValueConvertible?])
        arguments.append(contentsOf: ids as [DatabaseValueConvertible?])

        let learned = LinkKind.rawValues { kind in kind.isLearned }
        let kindPlaceholders = Array(repeating: "?", count: learned.count).joined(separator: ",")
        arguments.append(contentsOf: learned as [DatabaseValueConvertible?])

        let rows = try Row.fetchAll(db, sql: """
            SELECT src, dst, kind, weight FROM note_links
            WHERE src IN (\(placeholders)) AND dst IN (\(placeholders)) AND kind IN (\(kindPlaceholders))
            """, arguments: StatementArguments(arguments))
        var updated = 0

        for row in rows {
            let source: String = row["src"]
            let destination: String = row["dst"]
            let kind: String = row["kind"]
            let weight: Double = row["weight"]
            let factor = max(factorOf[source] ?? 1.0, factorOf[destination] ?? 1.0)
            let newWeight = min(cap, weight * factor)

            if newWeight > weight {
                try db.execute(sql: """
                    UPDATE note_links SET weight = ?, last_activated_at = ?
                    WHERE src = ? AND dst = ? AND kind = ?
                    """, arguments: [newWeight, now, source, destination, kind])
                updated += 1
            }
        }

        return updated
    }

    // MARK: - Private
}
