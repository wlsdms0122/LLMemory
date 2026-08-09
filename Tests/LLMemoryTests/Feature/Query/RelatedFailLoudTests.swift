//
//  RelatedFailLoudTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// An empty result and a brain that could not be read look identical to the caller unless the second
// one throws. related is the entry point of every retrieval descent, so it has to fail loud.
@Suite("RelatedFailLoud Tests", .serialized)
struct RelatedFailLoudTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a home that was never initialized refuses to connect instead of returning nothing")
    func relatedThrowsOnMissingBrain() {
        // Given — every query surface reaches the database through connect, so the
        // gate that used to live inside `related` now fires before it is even reachable.
        let uninitialized = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmemory-related-ghost-\(UUID().uuidString)").path
        let ghost = Session(home: uninitialized)
        
        // Then
        #expect(throws: DBError.self) {
            _ = try ghost.storage.connect()
        }
        
        // Rebind the fixture home so its teardown runs against its own paths.
        Paths.configure(home: home.path)
        Config.invalidateCache()
        Config.warmCache(home.storage)
    }
    
    @Test("related on a brain whose schema does not match the binary throws")
    func relatedThrowsOnSchemaMismatch() throws {
        // Given — a migration ledger that predates every registered migration.
        home.createNote(id: "gate-note")

        try home.database().write { database in
            try database.execute(sql: "DELETE FROM grdb_migrations")
        }

        home.storage.disconnect()

        // Then
        #expect(throws: DBError.self) {
            _ = try home.database().read { db in
                try home.container.retrieval.related(
                    GRDBReadScope(db),
                    text: "gate note",
                    kind: nil,
                    sessionId: nil,
                    includeBodies: false
                )
            }
        }

        // Restore the ledger so the fixture can tear the home down through a working connection.
        let raw = try DatabaseQueue(path: Paths.db.path)

        try raw.write { database in
            try database.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["1"]
            )
        }
    }
}
