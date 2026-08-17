//
//  SessionBindingTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("SessionBinding Tests", .serialized)
struct SessionBindingTests {
    // MARK: - Property
    private let home: MemoryHome

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("two sessions in one process own independent storages — neither sees the other's rows")
    func sessionsAreIndependent() throws {
        // Given
        try home.storage.writeLock {
            try home.storage.connect().write { database in
                try database.execute(
                    sql: "INSERT INTO meta (key, value) VALUES ('binding-probe', 'first')"
                )
            }
        }

        let second = try SecondaryHome()

        try second.storage.prepare()

        // When — write through the second session's storage only.
        try second.storage.writeLock {
            try second.storage.connect().write { database in
                try database.execute(
                    sql: "INSERT INTO meta (key, value) VALUES ('binding-probe', 'second')"
                )
            }
        }

        // Then
        let underFirst = try home.storage.connect().read { database in
            try String.fetchOne(database, sql: "SELECT value FROM meta WHERE key = 'binding-probe'")
        }
        let underSecond = try second.storage.connect().read { database in
            try String.fetchOne(database, sql: "SELECT value FROM meta WHERE key = 'binding-probe'")
        }

        #expect(underFirst == "first", "the second session's write leaked into the first database")
        #expect(underSecond == "second")

        // The queue can look right while the writes land in the wrong file, so read A's database
        // file directly rather than through the connection under test.
        let fileOfFirst = try DatabaseQueue(path: home.url.appendingPathComponent("data/memory.db").path)
        let strayValue = try fileOfFirst.read { database in
            try String.fetchOne(database, sql: "SELECT value FROM meta WHERE key = 'binding-probe'")
        }

        #expect(strayValue == "first", "the probe was written into the first session's database file")
    }

    // There is no ambient brain to move any more: paths and parameter caches
    // belong to the Session that owns them and arrive through the scope it
    // opens. Constructing another Session is not an event the first one can
    // observe — which is the whole difference from the version of this that
    // answered from a process-wide fallback.
    @Test("a second session is not something the first one can notice")
    func sessionsDoNotShareParameters() throws {
        // Given — a probe value primed into the fixture's own context
        try home.write { database in
            try SetConfigValueOperation(key: "binding-probe", value: "mine").execute(database)
        }

        home.session.rewarm()

        // When
        let second = try SecondaryHome()

        try second.storage.prepare()

        // Then
        #expect(home.layout.brainRoot == home.session.home)
        #expect(second.session.context.layout.brainRoot == second.session.home)
        #expect(home.layout.brainRoot != second.session.home, "two homes, two roots")
        #expect(home.config.getString("binding-probe", default: "") == "mine")
        #expect(second.session.context.config.getString("binding-probe", default: "") == "",
            "a second brain has its own cache, not a share of this one's")
    }

    @Test("a storage caches its connection — reconnecting yields the same queue")
    func storageCachesTheConnection() throws {
        // Given
        let before = try home.storage.connect() as? DatabaseQueue

        // When
        let after = try home.storage.connect() as? DatabaseQueue

        // Then
        #expect(before != nil && before === after, "connect must reuse the cached connection")
    }
}
