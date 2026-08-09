//
//  NoteMetaTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// Note metadata is namespaced key/value state that markdown does not carry. It is only ever a string,
// and it is only ever attached to a note that exists.
@Suite("NoteMeta Tests", .serialized)
struct NoteMetaTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("setting a value creates the row it can be read back from")
    func setCreatesRow() throws {
        // Given
        try seed("nm-set-1")
        
        // When
        let result = set(noteId: "nm-set-1", value: "normal")
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try value(of: "nm-set-1") == "normal")
    }
    
    @Test("setting the same key again replaces the value rather than adding a second row")
    func setUpsert() throws {
        // Given
        try seed("nm-upsert")
        
        // When
        for value in ["low", "normal", "high"] {
            #expect(set(noteId: "nm-upsert", value: value).status == "ok")
        }
        
        // Then
        #expect(try value(of: "nm-upsert") == "high")
    }
    
    @Test("metadata for an unknown note is refused rather than left orphaned")
    func unknownIdRejected() {
        // When
        let result = set(noteId: "no-such-note", value: "v")
        
        // Then
        #expect(result.status == "rejected")
        #expect(result.error.contains("unknown id"))
    }
    
    @Test("a namespace that is not a plain identifier is refused")
    func invalidNamespaceRejected() throws {
        // Given
        try seed("nm-ns-bad")
        
        // When
        let result = home.apply([
            "op": "set_note_meta", "id": "nm-ns-bad",
            "namespace": "Has Spaces!", "key": "k", "value": "v"
        ])
        
        // Then
        #expect(result.status == "rejected")
        #expect(result.error.contains("invalid namespace"))
    }
    
    @Test("a non-string value is refused rather than coerced into one")
    func valueMustBeString() throws {
        // Given
        try seed("nm-val-type")
        
        // When
        let result = home.apply([
            "op": "set_note_meta", "id": "nm-val-type",
            "namespace": "journal", "key": "affect", "value": 42
        ])
        
        // Then
        #expect(result.status == "rejected")
        #expect(result.error.contains("value must be string"))
    }
    
    @Test("deleting a key removes the row, so reading it back finds nothing")
    func deleteRemovesRow() throws {
        // Given
        try seed("nm-del")
        
        set(noteId: "nm-del", value: "x")
        
        // When
        let result = home.apply([
            "op": "delete_note_meta", "id": "nm-del", "namespace": "journal", "key": "affect"
        ])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try value(of: "nm-del") == nil)
    }
    
    // MARK: - Private
    private func seed(_ noteId: String, axis: String = "tech") throws {
        let result = home.createNote(id: noteId, axis: axis, title: noteId, tags: [axis, "test"], content: "b")
        
        guard result.status == "ok" else { throw TestFailure("seed \(noteId): \(result.error)") }
    }
    
    @discardableResult
    private func set(noteId: String, value: String) -> OperationsEngine.Result {
        home.apply([
            "op": "set_note_meta", "id": noteId,
            "namespace": "journal", "key": "affect", "value": value
        ])
    }
    
    private func value(of noteId: String) throws -> String? {
        try home.read { database in
            try FetchNoteMetaValueTransaction(noteId: noteId, namespace: "journal", key: "affect").perform(database)
        }
    }
}
