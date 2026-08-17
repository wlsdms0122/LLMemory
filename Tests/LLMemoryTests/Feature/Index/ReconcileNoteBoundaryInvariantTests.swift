//
//  ReconcileNoteBoundaryInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/18/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// An upsert is a dozen statements, and reconcile records a note's failure and
// carries on to the next one. Without a boundary of its own, the statements
// that ran before the failure would land in the enclosing commit — a row whose
// catalog entry exists and whose tags, entities and FTS projection do not.
//
// The operation claims no atomicity, so the boundary belongs to the caller that
// swallows the failure. This is the test that says so.
@Suite("ReconcileNoteBoundaryInvariant Tests", .serialized)
struct ReconcileNoteBoundaryInvariantTests {
    // MARK: - Property
    private let home: MemoryHome

    private let indexer = Indexer()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("a note that fails partway through its upsert leaves no row behind")
    func aFailedUpsertRollsBackWhole() throws {
        // Given — two unindexed notes, and a tag insert that refuses one of them.
        // The catalog row is written before the tags, so a failure there is
        // exactly the half-written state the boundary exists to prevent.
        try plant(id: "keeper")
        try plant(id: "doomed")
        try home.write { db in
            try db.execute(sql: """
                CREATE TEMP TRIGGER refuse_doomed BEFORE INSERT ON tags
                WHEN NEW.note_id = 'doomed'
                BEGIN SELECT RAISE(ABORT, 'refused'); END
                """)
        }

        // When
        let result = try indexer.buildLocked(home.database(), home.brain, rebuild: false)

        // Then — the failure was reported, and it took its whole note with it.
        let ids = try home.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM notes ORDER BY id")
        }

        #expect(result.errors.contains { message in message.contains("doomed") }, "\(result.errors)")
        #expect(ids.contains("keeper"), "the note that succeeded was rolled back too: \(ids)")
        #expect(!ids.contains("doomed"), "half of a failed upsert survived into the commit: \(ids)")
    }

    // MARK: - Private
    private func plant(id: String) throws {
        try """
            ---
            id: \(id)
            title: \(id)
            axis: flow
            priority: lazy
            tags: [flow]
            summary: \(id)
            ---

            body

            """
            .write(
                to: home.url.appendingPathComponent("cortex/\(id).md"),
                atomically: true,
                encoding: .utf8
            )
    }
}
