//
//  SchemaStampInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("SchemaStampInvariant Tests", .serialized)
struct SchemaStampInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("init on a shape-mismatched brain fails loud and withholds the version stamp")
    func initRefusesStaleShape() throws {
        // Given — a column the current schema requires is gone, and the file claims an old version.
        try home.database().write { database in
            try database.execute(sql: "ALTER TABLE note_source DROP COLUMN decl_hash")
            try database.execute(sql: "PRAGMA user_version = 1")
        }
        
        dropConnection()
        
        // When
        #expect(throws: DBError.self) {
            try DB.initDB()
        }
        
        // Then — the stamp must not advance, or the next run would trust a schema it never applied.
        #expect(try storedSchemaVersion() == 1)
        
        dropConnection()
        
        #expect(throws: DBError.self) { _ = try DB.connect() }
    }
    
    @Test("init on a purely additive delta reconciles the schema and stamps the new version")
    func initReconcilesAdditiveDelta() throws {
        // Given
        try home.database().write { database in
            try database.execute(sql: "DROP TABLE genome_events")
            try database.execute(sql: "PRAGMA user_version = 2")
        }
        
        dropConnection()
        
        // When
        try DB.initDB()
        
        // Then
        #expect(try storedSchemaVersion() == DB.schemaVersion)
        
        dropConnection()
        
        _ = try DB.connect()
    }
    
    @Test("a table that lost its CHECK constraint fails the shape predicate")
    func checkConstraintDriftIsCaught() throws {
        // Given
        try home.database().write { database in
            try database.execute(sql: "DROP TABLE rule")
            try database.execute(sql: """
                CREATE TABLE rule (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  ruleset_id TEXT NOT NULL REFERENCES ruleset(id) ON DELETE CASCADE,
                  kind TEXT NOT NULL,
                  params TEXT NOT NULL,
                  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
                  created_at INTEGER NOT NULL
                )
                """)
            try database.execute(sql: "CREATE INDEX idx_rule_ruleset ON rule(ruleset_id, enabled)")
            
            // When
            let messages = try DB.checkSchemaShape(database)
            
            // Then
            #expect(messages.contains { message in
                message.contains("ddl-mismatch") && message.contains("rule")
            }, "a missing CHECK passed as a shape match — got \(messages)")
        }
    }
    
    // MARK: - Private
    private func dropConnection() {
        DB.queue = nil
        DB.versionChecked = false
    }
    
    // Read through a fresh queue: the point is what the file says, not what the process remembers.
    private func storedSchemaVersion() throws -> Int {
        let raw = try DatabaseQueue(path: Paths.db.path)
        
        return try raw.read { database in try Int.fetchOne(database, sql: "PRAGMA user_version") ?? -1 }
    }
}
