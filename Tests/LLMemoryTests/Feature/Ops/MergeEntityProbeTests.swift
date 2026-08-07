//
//  MergeEntityProbeTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// An entity's hit count is observation, not something markdown can restate. A merge that lets the
// absorbed note's count fall on the floor loses it for good.
@Suite("MergeEntityProbe Tests", .serialized)
struct MergeEntityProbeTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("merging accumulates the absorbed note's entity hit count instead of dropping it")
    func mergeAccumulatesEntityHitCount() throws {
        // Given
        try seedEntityNote(id: "into-um", hitCount: 3)
        try seedEntityNote(id: "from-a", hitCount: 5)
        
        // When
        let result = home.apply([
            "op": "merge_notes", "into_id": "into-um", "from_ids": ["from-a"],
            "merged_content": "## body\nmerged zephyrtoken content\n",
            "summary": "summary", "tags": ["flow"]
        ])
        
        // Then
        #expect(result.status == "ok", "merge failed: \(result.error)")
        #expect(try hitCount(of: "into-um") == 8, "the absorbed note's count was dropped rather than added")
    }
    
    // MARK: - Private
    private func seedEntityNote(id: String, hitCount: Int) throws {
        try home.reindexFile(at: try home.writeNoteFile(
            id: id,
            body: "# body \(id)",
            entities: ["zephyrtoken"]
        ))
        try home.database().write { database in
            try database.execute(
                sql: "UPDATE entity_index SET hit_count = ? WHERE note_id = ? AND entity = 'zephyrtoken'",
                arguments: [hitCount, id]
            )
        }
    }
    
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
