//
//  PolicyTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("Policy Tests")
struct PolicyTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("surface and notSurface partition the corpus — every note is on exactly one side")
    func surfaceAndNotSurfacePartitionAllNotes() throws {
        // Given — an in-memory table is enough: the subject is the SQL the atoms emit, not the brain.
        let queue = try DatabaseQueue()
        
        try queue.write { database in
            try database.execute(sql: """
                CREATE TABLE notes (
                  id TEXT PRIMARY KEY, stale INTEGER,
                  template TEXT, locked INTEGER, priority TEXT
                )
                """)
            
            for (index, stale) in [0, 1].enumerated() {
                try database.execute(
                    sql: "INSERT INTO notes VALUES (?, ?, NULL, 0, 'lazy')",
                    arguments: ["n\(index + 1)", stale]
                )
            }
        }
        
        // When
        try queue.read { database in
            let total = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes")!
            let surfaced = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM notes WHERE \(Policy.surface(""))"
            )!
            let withheld = try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM notes WHERE \(Policy.notSurface(""))"
            )!
            let both = try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*) FROM notes \
                    WHERE (\(Policy.surface(""))) AND (\(Policy.notSurface("")))
                    """
            )!
            
            // Then
            #expect(surfaced + withheld == total, "surface + notSurface must cover every note")
            #expect(both == 0, "surface and notSurface must be disjoint")
            #expect(surfaced == 1, "only the stale=0 note is on the surface")
        }
    }
    
    @Test("each atom emits the predicate the rest of the codebase is composed from")
    func atomsEmitExpectedSQL() {
        // Then
        #expect(Policy.fresh("n") == "COALESCE(n.stale, 0) = 0")
        #expect(Policy.stale("n") == "COALESCE(n.stale, 0) = 1")
        #expect(Policy.eager("n") == "n.priority = 'eager'")
        #expect(Policy.notEager("n") == "n.priority != 'eager'")
        #expect(Policy.forgetExempt("n") == "n.template IS NULL AND n.locked = 0")
        #expect(Policy.surface("n") == "COALESCE(n.stale, 0) = 0")
        #expect(Policy.decayCandidate("a") ==
            "COALESCE(a.stale, 0) = 0 AND a.priority != 'eager' AND a.template IS NULL AND a.locked = 0")
        #expect(Policy.forgetExempt("") == "template IS NULL AND locked = 0")
    }
}
