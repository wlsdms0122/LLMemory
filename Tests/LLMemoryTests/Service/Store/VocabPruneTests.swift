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
    @Test("a vocabulary tag no note carries any more is pruned")
    func pruneDropsUnusedVocabularyTag() throws {
        // Given
        lifecycle.create("tdb-v1", extraTags: ["onlyhere"])
        
        #expect(try lifecycle.vocabularyContains("onlyhere"))
        
        home.apply(["op": "delete_note", "id": "tdb-v1", "reason": "leave the tag unused"])
        
        // When
        let result = try home.write { database in
            try PruneUnusedVocabTagsOperation().execute(database)
        }
        
        // Then
        #expect(result.contains("onlyhere"))
        #expect(try !lifecycle.vocabularyContains("onlyhere"))
    }
    
    @Test("a tag still carried by a note survives pruning")
    func pruneKeepsUsedVocabularyTag() throws {
        // Given
        lifecycle.create("tdb-v2", extraTags: ["stillused"])
        
        // When
        let result = try home.write { database in
            try PruneUnusedVocabTagsOperation().execute(database)
        }
        
        // Then
        #expect(!result.contains("stillused"))
        #expect(try lifecycle.vocabularyContains("stillused"))
    }
}
