//
//  RetrievalRecord.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
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
    public let sessionId: SessionId?
    public let activateIds: [String]
    public let strengthenPairs: [Pair]
    public let rebirthRanked: [Ranked]
    public let payloadJSON: String

    // MARK: - Initializer
    init(
        sessionId: SessionId?,
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
