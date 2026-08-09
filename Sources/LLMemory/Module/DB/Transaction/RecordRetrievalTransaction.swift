//
//  RecordRetrievalTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import Storage
import GRDB

// Retrieval side effects — usage activation, co-occurrence wiring, rebirth and
// the retrieval event — derived on the read path and applied here as the write
// half, so read transactions stay reads. Best-effort by contract: retrieval
// must not fail because its trace could not be written.
public struct RecordRetrievalTransaction: LegacyWriteTransaction {
    // MARK: - Property
    public let parameter: Parameter

    // MARK: - Initializer
    public init(_ parameter: Parameter) {
        self.parameter = parameter
    }

    // MARK: - Lifecycle
    public func execute(_ connection: Connection) async throws -> Result {
        try perform(connection)
    }

    // MARK: - Internal
    // Sync body — also the direct surface for synchronous unit tests.
    // Usage activation is the one mandatory state transition (fail-loud, as before
    // the split); strengthening and rebirth are advisory learning signals and the
    // event is a trace — those stay best-effort, surfaced through the result.
    func perform(_ connection: Connection) throws -> Result {
        let now = Int(Date().timeIntervalSince1970)
        var degraded: [String] = []

        if !parameter.activateIds.isEmpty {
            try connection.write { db in
                try ActivateNotesTransaction(ids: parameter.activateIds, now: now).perform(db)
            }
        }

        if !parameter.strengthenPairs.isEmpty {
            do {
                _ = try connection.write { db in
                    try StrengthenLinksTransaction(
                        pairs: parameter.strengthenPairs.map { pair in (pair.source, pair.destination) },
                        cap: 1.0
                    )
                        .perform(db)
                }
            } catch {
                degraded.append("strengthen: \(error)")
            }
        }

        if parameter.rebirthRanked.count >= 2 {
            do {
                _ = try connection.write { db in
                    try RebirthLinksTransaction(
                        rankedIds: parameter.rebirthRanked.map { ranked in (ranked.id, ranked.factor) }
                    )
                        .perform(db)
                }
            } catch {
                degraded.append("rebirth: \(error)")
            }
        }

        Events.record(
            connection,
            kind: Events.kindRetrieval,
            payloadJSON: parameter.payloadJSON,
            sessionId: parameter.sessionId,
            ts: now
        )

        return degraded
    }
}

public extension RecordRetrievalTransaction {
    // The record is derived on the read path — the query tier owns its shape;
    // this transaction adapts it as its parameter.
    typealias Parameter = Retrieval.Record
    typealias Pair = Retrieval.Record.Pair
    typealias Ranked = Retrieval.Record.Ranked

    typealias Result = [String]
}
