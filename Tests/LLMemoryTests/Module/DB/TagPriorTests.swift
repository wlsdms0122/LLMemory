//
//  TagPriorTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/13/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// The session prior is contextual reinstatement: what a session has been touching lately
// gets a nudge. It runs over tags because a note belongs to as many contexts as it has
// tags — reading one drawer is not the same as reading one subject.
@Suite("TagPrior Tests", .serialized)
struct TagPriorTests {
    // MARK: - Property
    private let home: MemoryHome

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("the prior counts every tag of every recently surfaced note, normalised to 1")
    func priorSpreadsOverAllTagsOfAHit() throws {
        // Given
        home.createNote(id: "tp-a", axis: "flow", tags: ["flow", "transfer"])
        home.createNote(id: "tp-b", axis: "tech", tags: ["tech"])

        try recordRetrieval(session: "s1", hits: ["tp-a", "tp-b"])

        // When
        let prior = try home.read { database in
            try ComputeTagPriorTransaction(sessionId: "s1", windowSec: 3600, now: now)
                .perform(database)
        }

        // Then — three tag occurrences across the two hits
        #expect(prior["flow"] == 1.0 / 3.0)
        #expect(prior["transfer"] == 1.0 / 3.0)
        #expect(prior["tech"] == 1.0 / 3.0)
        #expect(prior.values.reduce(0, +) == 1.0)
    }

    @Test("another session's retrievals do not warm this one")
    func priorIsScopedToItsSession() throws {
        // Given
        home.createNote(id: "tp-c", axis: "flow", tags: ["flow"])

        try recordRetrieval(session: "other", hits: ["tp-c"])

        // When
        let prior = try home.read { database in
            try ComputeTagPriorTransaction(sessionId: "mine", windowSec: 3600, now: now)
                .perform(database)
        }

        // Then
        #expect(prior.isEmpty)
    }

    // MARK: - Private
    private var now: Int { Int(Date().timeIntervalSince1970) }

    private func recordRetrieval(session: String, hits: [String]) throws {
        let payload = String(
            data: try JSONSerialization.data(withJSONObject: ["hit_ids": hits]),
            encoding: .utf8
        )!

        try home.write { database in
            try database.execute(sql: """
                INSERT INTO events (ts, kind, session_id, payload) VALUES (?, 'retrieval', ?, ?)
                """, arguments: [now, session, payload])
        }
    }
}
