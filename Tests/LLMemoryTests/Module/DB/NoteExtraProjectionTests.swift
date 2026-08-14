//
//  NoteExtraProjectionTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/13/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// A note may carry frontmatter fields llmemory has no opinion about. The file owns them;
// note_extra is the queryable mirror, so it has to be a pure function of the file — it
// follows an edit, and a rebuild that has only the markdown reproduces it exactly.
@Suite("NoteExtraProjection Tests", .serialized)
struct NoteExtraProjectionTests {
    // MARK: - Property
    private let home: MemoryHome

    private let indexer = Indexer()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("a custom frontmatter field lands in note_extra and follows the file when it changes")
    func customFieldProjectsAndFollowsEdits() throws {
        // Given
        home.createNote(id: "nx-a", tags: ["flow"])

        #expect(home.apply([
            "op": "set_frontmatter", "id": "nx-a", "fields": ["affect": "high", "wave": 3]
        ]).status == "ok")

        // Then
        #expect(try extras(of: "nx-a") == ["affect": "high", "wave": "3"])

        // When — the value changes, and one field is removed outright
        #expect(home.apply([
            "op": "set_frontmatter", "id": "nx-a", "fields": ["affect": "low", "wave": NSNull()]
        ]).status == "ok")

        // Then
        #expect(try extras(of: "nx-a") == ["affect": "low"])
    }

    @Test("create_note keeps a custom field too — the note owns it from birth")
    func createCarriesCustomFields() throws {
        // When
        home.createNote(id: "nx-born", tags: ["flow"], fields: ["affect": "high"])

        // Then
        #expect(try extras(of: "nx-born") == ["affect": "high"])
    }

    @Test("a rebuild from markdown alone reproduces note_extra — the file is the source")
    func rebuildReproducesFromMarkdown() throws {
        // Given
        home.createNote(id: "nx-b", tags: ["flow"])

        #expect(home.apply([
            "op": "set_frontmatter", "id": "nx-b", "fields": ["affect": "normal"]
        ]).status == "ok")

        // When — wipe the projection and rebuild from the files
        try home.write { database in try database.execute(sql: "DELETE FROM note_extra") }

        #expect(try extras(of: "nx-b").isEmpty)

        _ = try indexer.buildLocked(try home.storage.connect(), rebuild: true)

        // Then
        #expect(try extras(of: "nx-b") == ["affect": "normal"])
    }

    @Test("the list filter matches a custom field by key, and by key and value together")
    func listFilterMatchesCustomFields() throws {
        // Given
        home.createNote(id: "nx-high", tags: ["flow"])
        home.createNote(id: "nx-low", tags: ["flow"])
        home.createNote(id: "nx-none", tags: ["flow"])

        #expect(home.apply([
            "op": "set_frontmatter", "id": "nx-high", "fields": ["affect": "high"]
        ]).status == "ok")
        #expect(home.apply([
            "op": "set_frontmatter", "id": "nx-low", "fields": ["affect": "low"]
        ]).status == "ok")

        // Then
        #expect(try listed(.init(key: "affect", value: nil)) == ["nx-high", "nx-low"])
        #expect(try listed(.init(key: "affect", value: "high")) == ["nx-high"])
        #expect(try listed(.init(key: "nosuchfield", value: nil)).isEmpty)
    }

    // MARK: - Private
    private func extras(of noteId: String) throws -> [String: String] {
        try home.read { database in
            var found: [String: String] = [:]

            for row in try Row.fetchAll(
                database,
                sql: "SELECT key, value FROM note_extra WHERE note_id = ?",
                arguments: [noteId]
            ) {
                found[row["key"] as String] = row["value"] as String
            }

            return found
        }
    }

    private func listed(_ field: NoteFieldFilter) throws -> [String] {
        try home.read { database in
            try ListNoteRowsTransaction(.init(fields: [field]))
                .perform(database)
                .map { row in row.id }
        }
    }
}
