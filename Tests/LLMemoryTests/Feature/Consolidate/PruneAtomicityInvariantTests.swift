//
//  PruneAtomicityInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("PruneAtomicityInvariant Tests", .serialized)
struct PruneAtomicityInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a decay tick joins the caller's transaction — rolling that back undoes the decay too")
    func decayRollsBackWithCallerTransaction() throws {
        // Given
        let queue = try home.database()
        
        try queue.write { database in try seedAssocLink(database, weight: 1.0) }
        
        // When
        #expect(throws: RollbackSignal.self) {
            try queue.write { database in
                _ = try Links.decayAndPrune(database, factor: 0.5, floor: 0.0)
                
                #expect(try Self.linkWeight(database) == 0.5, "decay is visible inside the transaction")
                
                throw RollbackSignal()
            }
        }
        
        // Then
        let after = try queue.read { database in try Self.linkWeight(database) }
        
        #expect(after == 1.0, "a rolled-back tick must leave the link weight untouched")
    }
    
    @Test("prune decays learned links and reports the count it committed")
    func pruneDecaysLinksAndReportsIt() throws {
        // Given
        try home.write { database in try seedAssocLink(database, weight: 1.0) }
        
        // When
        let result = try Consolidate.pruneLocked()
        
        // Then
        let weight = try home.read { database in try Self.linkWeight(database) }
        
        #expect(weight == 0.9, "the default links.decay_factor of 0.9 applies")
        #expect(result.linksDecayed >= 1, "the result must report the decay it committed")
    }
    
    // MARK: - Private
    // Written straight into the tables rather than through ops: the subject is the decay tick, and a
    // link with a known starting weight is what it needs.
    private func seedAssocLink(_ database: Database, weight: Double) throws {
        try database.execute(
            sql: "INSERT OR IGNORE INTO axes (axis, description, created_at) VALUES ('flow', 'flow', ?)",
            arguments: [home.now]
        )
        
        for noteId in ["patom-a", "patom-b"] {
            try database.execute(sql: """
                INSERT INTO notes (id, axis, path, title, summary, priority, file_mtime, indexed_at)
                VALUES (?, 'flow', ?, ?, '', 'lazy', ?, ?)
                """, arguments: [noteId, "tmp/\(noteId).md", noteId, home.now, home.now])
        }
        
        try database.execute(sql: """
            INSERT INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
            VALUES ('patom-a', 'patom-b', ?, ?, ?, ?)
            """, arguments: [Links.kindAssoc, weight, home.now, home.now])
    }
    
    private static func linkWeight(_ database: Database) throws -> Double? {
        try Double.fetchOne(
            database,
            sql: "SELECT weight FROM note_links WHERE src = 'patom-a' AND dst = 'patom-b'"
        )
    }
}
