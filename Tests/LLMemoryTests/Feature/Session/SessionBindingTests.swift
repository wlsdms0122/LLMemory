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
        try home.storage.write { database in
            try database.execute(
                sql: "INSERT INTO meta (key, value) VALUES ('binding-probe', 'first')"
            )
        }

        let second = try SecondaryHome()

        try second.storage.initialize()

        // When — write through the second session's storage only.
        try second.storage.write { database in
            try database.execute(
                sql: "INSERT INTO meta (key, value) VALUES ('binding-probe', 'second')"
            )
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

        // Constructing the second session moved the process-global Paths remnant; put it back
        // so the fixture tears down against its own home.
        Paths.configure(home: home.path)
        Config.invalidateCache()
        Config.warmCache(home.storage)
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
