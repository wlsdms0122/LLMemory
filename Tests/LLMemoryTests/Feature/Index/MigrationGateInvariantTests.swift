//
//  MigrationGateInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("MigrationGateInvariant Tests", .serialized)
struct MigrationGateInvariantTests {
    // MARK: - Property
    private let home: MemoryHome

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("initialize on a shape-mismatched brain fails loud — IF NOT EXISTS cannot reconcile a diverged table")
    func initializeRefusesDivergedShape() throws {
        // Given — a column the current schema requires is gone.
        try home.write { database in
            try database.execute(sql: "ALTER TABLE note_source DROP COLUMN decl_hash")
        }

        dropConnection()

        // When
        #expect(throws: DBError.self) {
            try home.storage.initialize()
        }

        // Then — the drift stays visible to the verify layer.
        let messages = try home.read { database in
            try SchemaShape(migrations: Session.migrations).check(database)
        }

        #expect(messages.contains { message in message.contains("column-missing") })
    }

    // The stampless design re-ran the baseline DDL on every init and silently resurrected
    // dropped tables. Under migrations an applied migration never re-runs, and re-running
    // the baseline against an evolved schema would resurrect tables later migrations
    // removed — so a missing table is corruption, surfaced loudly, repaired via rebuild.
    @Test("initialize does not silently resurrect a dropped table — the drift fails loud")
    func initializeRefusesMissingTable() throws {
        // Given
        try home.write { database in
            try database.execute(sql: "DROP TABLE genome_events")
        }

        dropConnection()

        // When
        #expect(throws: DBError.self) {
            try home.storage.initialize()
        }

        // Then
        let messages = try home.read { database in
            try SchemaShape(migrations: Session.migrations).check(database)
        }

        #expect(messages.contains { message in message.contains("table-missing") })
    }

    @Test("connect refuses a brain whose migrations are behind this binary")
    func connectRefusesPendingMigrations() throws {
        // Given — a brain whose migration ledger predates every registered migration.
        try home.write { database in
            try database.execute(sql: "DELETE FROM grdb_migrations")
        }

        dropConnection()

        // When / Then
        #expect(throws: DBError.self) { _ = try home.storage.connect() }
    }

    @Test("connect refuses a brain migrated by a newer binary")
    func connectRefusesSupersededBrain() throws {
        // Given — a migration record this binary has never heard of.
        try home.write { database in
            try database.execute(
                sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)",
                arguments: ["999"]
            )
        }

        dropConnection()

        // When / Then
        #expect(throws: DBError.self) { _ = try home.storage.connect() }
    }

    @Test("a table that lost its CHECK constraint fails the shape predicate")
    func checkConstraintDriftIsCaught() throws {
        // Given
        try home.database().write { database in
            try database.execute(sql: "DROP TABLE note_retrieval_terms")
            try database.execute(sql: """
                CREATE TABLE note_retrieval_terms (
                  note_id    TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                  kind       TEXT NOT NULL,
                  term       TEXT NOT NULL,
                  status     TEXT NOT NULL DEFAULT 'pending',
                  provenance TEXT,
                  reject_reason TEXT,
                  created_at   INTEGER NOT NULL,
                  validated_at INTEGER,
                  PRIMARY KEY (note_id, kind, term)
                )
                """)
            try database.execute(sql: "CREATE INDEX idx_nrt_status ON note_retrieval_terms(status)")
            try database.execute(sql: "CREATE INDEX idx_nrt_status_created ON note_retrieval_terms(status, created_at)")
            try database.execute(sql: "CREATE INDEX idx_nrt_provenance ON note_retrieval_terms(provenance)")

            // When
            let messages = try SchemaShape(migrations: Session.migrations).check(database)

            // Then
            #expect(messages.contains { message in
                message.contains("ddl-mismatch") && message.contains("note_retrieval_terms")
            }, "a missing CHECK passed as a shape match — got \(messages)")
        }
    }

    // MARK: - Private
    private func dropConnection() {
        home.storage.disconnect()
    }
}
