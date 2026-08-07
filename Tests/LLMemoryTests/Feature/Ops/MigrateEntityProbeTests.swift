//
//  MigrateEntityProbeTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("MigrateEntityProbe Tests", .serialized)
struct MigrateEntityProbeTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("renaming a note carries its entity hit count across — the count cannot be re-derived")
    func migratePreservesEntityHitCount() throws {
        // Given
        try home.reindexFile(at: try home.writeNoteFile(
            id: "ent-src",
            body: "# body",
            entities: ["zephyrtoken"]
        ))
        try home.database().write { database in
            try database.execute(sql: """
                UPDATE entity_index SET hit_count = 5
                WHERE note_id = 'ent-src' AND entity = 'zephyrtoken'
                """)
        }
        
        #expect(try hitCount(of: "ent-src") == 5, "setup: the source count should be 5")
        
        // When
        let migrated = home.apply(["op": "migrate_note", "id": "ent-src", "new_id": "ent-dst"])
        
        // Then
        #expect(migrated.status == "ok", "\(migrated.error)")
        #expect(try hitCount(of: "ent-dst") == 5, "migrate lost the accumulated entity hit count")
    }
    
    // MARK: - Private
    private func hitCount(of noteId: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT hit_count FROM entity_index WHERE note_id = ? AND entity = 'zephyrtoken'",
                arguments: [noteId]
            ) ?? -1
        }
    }
}
