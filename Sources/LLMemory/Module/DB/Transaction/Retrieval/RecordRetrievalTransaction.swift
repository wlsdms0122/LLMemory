//
//  RecordRetrievalTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

// Applies the derived record. Best-effort by contract: usage activation is
// the one mandatory state transition (fail-loud); strengthening and rebirth
// are advisory learning signals and the event is a trace — those stay
// best-effort, surfaced through the returned degraded notes.
struct RecordRetrievalTransaction: GRDBTransaction {
    // MARK: - Property
    let record: RetrievalRecord

    private let events = Events()

    // MARK: - Initializer
    init(_ record: RetrievalRecord) {
        self.record = record
    }

    // MARK: - Public
    func perform(_ db: Database) throws -> [String] {
        let now = Int(Date().timeIntervalSince1970)
        var degraded: [String] = []

        if !record.activateIds.isEmpty {
            try ActivateNotesTransaction(ids: record.activateIds, now: now).perform(db)
        }

        if !record.strengthenPairs.isEmpty {
            do {
                _ = try StrengthenLinksTransaction(
                    pairs: record.strengthenPairs.map { pair in (pair.source, pair.destination) },
                    cap: 1.0
                )
                    .perform(db)
            } catch {
                degraded.append("strengthen: \(error)")
            }
        }

        if record.rebirthRanked.count >= 2 {
            do {
                _ = try RebirthLinksTransaction(
                    rankedIds: record.rebirthRanked.map { ranked in (ranked.id, ranked.factor) }
                )
                    .perform(db)
            } catch {
                degraded.append("rebirth: \(error)")
            }
        }

        events.record(
            db,
            kind: Events.kindRetrieval,
            payloadJSON: record.payloadJSON,
            sessionId: record.sessionId,
            ts: now
        )

        return degraded
    }

    // MARK: - Private
}
