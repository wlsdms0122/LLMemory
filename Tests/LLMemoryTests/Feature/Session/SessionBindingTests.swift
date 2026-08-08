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
    @Test("rebinding the home swaps the database — neither home sees the other's rows")
    func rebindingSwapsTheDatabase() throws {
        // Given
        home.createNote(id: "a-note")
        
        let second = try SecondaryHome()
        
        Session.configure(home: second.path)
        
        try GRDBStorage.session.initialize()
        
        // initialize drops the connection and leaves the config cache cold, so the home has to be bound
        // again before anything reads it — an op that hits a cold Config would open a second
        // connection from inside its own write.
        Session.configure(home: second.path)
        
        // When
        second.createNote(id: "b-note")
        
        let idsUnderSecond = try Self.noteIds()
        
        Session.configure(home: home.path)
        
        let idsUnderFirst = try Self.noteIds()
        
        // Then
        #expect(idsUnderSecond.contains("b-note"))
        #expect(!idsUnderSecond.contains("a-note"), "seeing A's rows under B means the queue never swapped")
        #expect(idsUnderFirst.contains("a-note"))
        #expect(!idsUnderFirst.contains("b-note"), "seeing B's rows under A means the queue never swapped")
        
        // The queue can look right while the writes land in the wrong file, so read A's database file
        // directly rather than through the connection under test.
        let fileOfFirst = try DatabaseQueue(path: home.url.appendingPathComponent("data/memory.db").path)
        let strayRows = try fileOfFirst.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes WHERE id = 'b-note'") ?? 0
        }
        
        #expect(strayRows == 0, "b-note was written into A's database file")
    }
    
    @Test("reconfiguring the same home keeps the connection — no warm-cache thrash")
    func sameHomeKeepsTheConnection() throws {
        // Given
        let before = try GRDBStorage.session.connect()
        
        // When
        Session.configure(home: home.path)
        
        let after = try GRDBStorage.session.connect()
        
        // Then
        #expect(before === after, "reconfiguring the same home must not replace the connection")
    }
    
    // MARK: - Private
    private static func noteIds() throws -> Set<String> {
        try GRDBStorage.session.connect().read { database in
            Set(try String.fetchAll(database, sql: "SELECT id FROM notes"))
        }
    }
}
