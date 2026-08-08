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
    @Test("related on a home that was never initialized throws instead of returning nothing")
    func relatedThrowsOnMissingBrain() {
        // Given
        let uninitialized = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmemory-related-ghost-\(UUID().uuidString)").path
        
        Session.configure(home: uninitialized)
        
        // Then
        #expect(throws: (any Error).self) {
            _ = try QueryFeature.related(
                text: "transfer flow",
                kind: nil,
                cliSessionId: "",
                includeBodies: false
            )
        }
        
        // Rebind the fixture home so its teardown runs through a working connection.
        Session.configure(home: home.path)
    }
    
    @Test("related on a brain whose schema does not match the binary throws")
    func relatedThrowsOnSchemaMismatch() throws {
        // Given — a migration ledger that predates every registered migration.
        home.createNote(id: "gate-note")

        try home.database().write { database in
            try database.execute(sql: "DELETE FROM grdb_migrations")
        }

        GRDBStorage.session.disconnect()

        // Then
        #expect(throws: DBError.self) {
            _ = try QueryFeature.related(
                text: "gate note",
                kind: nil,
                cliSessionId: "",
                includeBodies: false
            )
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
