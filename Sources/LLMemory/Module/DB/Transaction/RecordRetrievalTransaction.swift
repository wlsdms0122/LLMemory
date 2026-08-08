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
public struct RecordRetrievalTransaction: GRDBWriteTransaction {
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
    func perform(_ connection: Connection) throws -> Result {
        let now = Int(Date().timeIntervalSince1970)

        if !parameter.activateIds.isEmpty {
            try? connection.write { db in
                try Notes.activate(db, ids: parameter.activateIds, now: now)
            }
        }

        if !parameter.strengthenPairs.isEmpty {
            _ = try? Links.strengthen(
                connection,
                pairs: parameter.strengthenPairs.map { pair in (pair.source, pair.destination) },
                cap: 1.0
            )
        }

        if parameter.rebirthRanked.count >= 2 {
            _ = try? Links.rebirth(
                connection,
                rankedIds: parameter.rebirthRanked.map { ranked in (ranked.id, ranked.factor) }
            )
        }

        Events.record(
            connection,
            kind: Events.kindRetrieval,
            payloadJSON: parameter.payloadJSON,
            sessionId: parameter.sessionId,
            ts: now
        )
    }
}

public extension RecordRetrievalTransaction {
    struct Parameter: Sendable {
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
    }

    struct Pair: Sendable {
        // MARK: - Property
        public let source: String
        public let destination: String

        // MARK: - Initializer
        init(_ source: String, _ destination: String) {
            self.source = source
            self.destination = destination
        }
    }

    struct Ranked: Sendable {
        // MARK: - Property
        public let id: String
        public let factor: Double

        // MARK: - Initializer
        init(_ id: String, _ factor: Double) {
            self.id = id
            self.factor = factor
        }
    }

    typealias Result = Void
}
