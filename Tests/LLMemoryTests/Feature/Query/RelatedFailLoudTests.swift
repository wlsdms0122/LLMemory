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
        
        // Then
        #expect(throws: (any Error).self) {
            _ = try QueryFeature.related(
                home: uninitialized,
                text: "transfer flow",
                kind: nil,
                cliSessionId: "",
                includeBodies: false
            )
        }
        
        // The call above rebinds the process to the ghost home; put it back for the fixture's teardown.
        Session.configure(home: home.path)
    }
    
    @Test("related on a brain whose schema does not match the binary throws")
    func relatedThrowsOnSchemaMismatch() throws {
        // Given
        home.createNote(id: "gate-note")
        
        try home.database().write { database in
            try database.execute(sql: "PRAGMA user_version = 1")
        }
        
        DB.queue = nil
        DB.versionChecked = false
        
        // Then
        #expect(throws: DBError.self) {
            _ = try QueryFeature.related(
                home: home.path,
                text: "gate note",
                kind: nil,
                cliSessionId: "",
                includeBodies: false
            )
        }
        
        // Restore the stamp so the fixture can tear the home down through a working connection.
        let raw = try DatabaseQueue(path: Paths.db.path)
        
        try raw.write { database in
            try database.execute(sql: "PRAGMA user_version = \(DB.schemaVersion)")
        }
    }
}
