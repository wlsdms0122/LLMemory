//
//  PruneTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Storage
import GRDB

public struct PruneTransaction: GRDBWriteTransaction {
    // MARK: - Initializer
    public init() { }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Private
    private func perform(_ connection: Connection) throws -> Result {
        let now = Int(Date().timeIntervalSince1970)
        var decay: (decayed: Int, pruned: Int) = (0, 0)

        try connection.write { db in
            decay = try Links.decayAndPrune(db)
        }

        Events.record(
            kind: Events.kindConsolidation,
            payload: [
                "action": "prune",
                "links_decayed": decay.decayed,
                "links_pruned": decay.pruned
            ],
            ts: now
        )

        return Consolidate.PruneResult(linksDecayed: decay.decayed, linksPruned: decay.pruned)
    }
}

public extension PruneTransaction {
    typealias Parameter = Void
    typealias Result = Consolidate.PruneResult
}
