//
//  RecordRetrievalOperation.swift
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
struct RecordRetrievalOperation: GRDBOperation {
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
    func execute(_ db: Database) throws -> [String] {
        let now = Int(Date().timeIntervalSince1970)
        var degraded: [String] = []

        if !record.activateIds.isEmpty {
            try ActivateNotesOperation(ids: record.activateIds, now: now).execute(db)
        }

        if !record.strengthenPairs.isEmpty {
            do {
                _ = try StrengthenLinksOperation(
                    pairs: record.strengthenPairs.map { pair in (pair.source, pair.destination) },
                    step: strengthenStep,
                    cap: 1.0
                )
                    .execute(db)
            } catch {
                degraded.append("strengthen: \(error)")
            }
        }

        if record.rebirthRanked.count >= 2 {
            do {
                _ = try RebirthLinksOperation(
                    ranked: record.rebirthRanked.map { ranked in (ranked.id, ranked.factor) },
                    defaultFactor: rebirthFactor
                )
                    .execute(db)
            } catch {
                degraded.append("rebirth: \(error)")
            }
        }

        do {
            try RecordEventOperation(
                kind: .retrieval,
                payload: record.payload,
                sessionId: record.sessionId,
                ts: now
            )
                .execute(db)
        } catch {
            degraded.append("event: \(error)")
        }

        return degraded
    }

    // MARK: - Private
}
