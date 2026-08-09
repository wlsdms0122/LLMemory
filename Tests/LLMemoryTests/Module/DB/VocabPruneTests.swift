//
//  VocabPruneTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("VocabPrune Tests", .serialized)
struct VocabPruneTests {
    // MARK: - Property
    private let home: MemoryHome
    private let lifecycle: NoteLifecycle
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        lifecycle = NoteLifecycle(home)
    }
    
    // MARK: - Test
    @Test("an axis left empty by a delete is pruned")
    func pruneEmptyAxesDropsEmptyAxis() throws {
        // Given
        lifecycle.create("tdb-h1", axis: "tdbaxis", axisDescription: "temporary")
        
        home.apply(["op": "delete_note", "id": "tdb-h1", "reason": "leave the axis empty"])
        
        #expect(try lifecycle.axisExists("tdbaxis"))
        
        // When
        let result = try home.database().write { database in try PruneEmptyAxesTransaction().perform(database) }
        
        // Then
        #expect(result.contains("tdbaxis"))
        #expect(try !lifecycle.axisExists("tdbaxis"))
    }
    
    @Test("an explicitly protected axis survives pruning even when empty")
    func pruneEmptyAxesHonorsProtectedSet() throws {
        // Given
        lifecycle.create("tdb-h2", axis: "keepaxis", axisDescription: "protected")

        home.apply(["op": "delete_note", "id": "tdb-h2", "reason": "leave the axis empty"])

        #expect(try lifecycle.axisExists("keepaxis"))

        // When
        let result = try home.database().write { database in
            try PruneEmptyAxesTransaction(protected: ["keepaxis"]).perform(database)
        }

        // Then
        #expect(!result.contains("keepaxis"))
        #expect(try lifecycle.axisExists("keepaxis"))
    }
}
