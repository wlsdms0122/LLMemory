//
//  SectionInvariantExitInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// The section-path invariant guards what a note becomes. A note that already carries a duplicate
// heading must still be able to leave — otherwise the guard traps the very notes it should let go.
@Suite("SectionInvariantExitInvariant Tests", .serialized)
struct SectionInvariantExitInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a note that already has a duplicate heading can still be deleted")
    func aNoteWithADuplicateHeadingCanStillBeDeleted() throws {
        // Given
        try seedCollidingNote(id: "cd-note")
        
        // When
        let result = home.apply(["op": "delete_note", "id": "cd-note", "reason": "test"])
        
        // Then
        #expect(result.status == "ok",
            "the note's own pre-existing collision blocked its own removal: \(result.error)")
    }
    
    @Test("a deleted note that has a duplicate heading can be restored — soft delete is not one-way")
    func aNoteWithADuplicateHeadingCanBeRestoredAfterDeletion() throws {
        // Given
        try seedCollidingNote(id: "cr-note")
        
        #expect(home.apply(["op": "delete_note", "id": "cr-note", "reason": "test"]).status == "ok")
        
        // When
        let result = home.apply(["op": "restore", "id": "cr-note"])
        
        // Then
        #expect(result.status == "ok", "soft delete turned out to be one-way: \(result.error)")
        #expect(try home.read { database in try NoteExistsTransaction(nid: "cr-note").perform(database) })
    }
    
    @Test("a note that already has a duplicate heading can still be migrated to another axis")
    func aNoteWithADuplicateHeadingCanBeMigrated() throws {
        // Given
        try seedCollidingNote(id: "cm-note")
        
        // When
        let result = home.apply([
            "op": "migrate_note", "id": "cm-note", "to_axis": "tech", "reason": "test"
        ])
        
        // Then
        #expect(result.status == "ok", "the note's own collision blocked its migration: \(result.error)")
    }
    
    @Test("introducing a collision into a live note is still refused")
    func aCollisionIntroducedIntoALiveNoteStillRollsBack() {
        // Given
        home.createNote(id: "cl-note", content: "## A\nx\n## B\ny\n")
        
        // When
        let result = home.apply([
            "op": "rename_section", "id": "cl-note", "section": "## B", "new_title": "A"
        ])
        
        // Then
        #expect(result.status != "ok", "a newly introduced section path collision was committed")
    }
    
    // MARK: - Private
    private func seedCollidingNote(id: String) throws {
        home.createNote(id: id, content: "## A\nx\n")
        
        try home.overwriteBody(of: id, with: "## A\nx\n## A\ny\n")
        try home.reindexNote(id: id)
    }
}
