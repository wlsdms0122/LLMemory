//
//  RecordRetrievalTransaction.swift
//  LLMemory
//
//  Created by JSilver on 8/9/26.
//

import Foundation
import GRDB

// The retrieval side effects, derived as data on the read path — usage
// activation, co-occurrence pairs, rebirth ranking and the retrieval event
// payload. RecordRetrievalTransaction applies it on the write path.
public struct RetrievalRecord: Sendable {
    public struct Pair: Sendable {
        // MARK: - Property
        public let source: String
        public let destination: String

        // MARK: - Initializer
        init(_ source: String, _ destination: String) {
            self.source = source
            self.destination = destination
        }

        // MARK: - Public
        // MARK: - Private
    }

    public struct Ranked: Sendable {
        // MARK: - Property
        public let id: String
        public let factor: Double

        // MARK: - Initializer
        init(_ id: String, _ factor: Double) {
            self.id = id
            self.factor = factor
        }

        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    public let sessionId: String?
    public let activateIds: [String]
    public let strengthenPairs: [Pair]
    public let rebirthRanked: [Ranked]
    public let payloadJSON: String

    // MARK: - Initializer
    init(
        sessionId: String?,
        activateIds: [String] = [],
        strengthenPairs: [Pair] = [],
        rebirthRanked: [Ranked] = [],
        payloadJSON: String
    ) {
        self.sessionId = sessionId
        self.activateIds = activateIds
        self.strengthenPairs = strengthenPairs
        self.rebirthRanked = rebirthRanked
        self.payloadJSON = payloadJSON
    }

    // MARK: - Public
    // MARK: - Private
}

// Applies the derived record. Best-effort by contract: usage activation is
// the one mandatory state transition (fail-loud); strengthening and rebirth
// are advisory learning signals and the event is a trace — those stay
// best-effort, surfaced through the returned degraded notes.
struct RecordRetrievalTransaction: GRDBTransaction {
    // MARK: - Property
    let record: RetrievalRecord

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

        Events.record(
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
