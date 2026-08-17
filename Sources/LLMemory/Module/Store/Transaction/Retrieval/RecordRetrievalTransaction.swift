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
    let strengthenStep: Double
    let rebirthFactor: Double

    // MARK: - Initializer
    init(_ record: RetrievalRecord, strengthenStep: Double, rebirthFactor: Double) {
        self.record = record
        self.strengthenStep = strengthenStep
        self.rebirthFactor = rebirthFactor
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
                    step: strengthenStep,
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
                    ranked: record.rebirthRanked.map { ranked in (ranked.id, ranked.factor) },
                    defaultFactor: rebirthFactor
                )
                    .perform(db)
            } catch {
                degraded.append("rebirth: \(error)")
            }
        }

        do {
            try RecordEventTransaction(
                kind: .retrieval,
                payload: record.payload,
                sessionId: record.sessionId,
                ts: now
            )
                .perform(db)
        } catch {
            degraded.append("event: \(error)")
        }

        return degraded
    }

    // MARK: - Private
}
