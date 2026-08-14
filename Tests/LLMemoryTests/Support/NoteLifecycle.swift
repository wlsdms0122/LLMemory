//
//  NoteLifecycle.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
@testable import LLMemory

// Reads the catalog rows that tag lifecycle work moves around, and creates the notes those
// tests need. Kept apart from the tests so the assertions read as claims rather than as SQL.
struct NoteLifecycle {
    // MARK: - Property
    private let home: any BrainHome
    
    private let frontmatter = Frontmatter()

    // MARK: - Initializer
    init(_ home: any BrainHome) {
        self.home = home
    }
    
    // MARK: - Public
    @discardableResult
    func create(
        _ noteId: String,
        tag: String = "flow",
        extraTags: [String] = []
    ) -> OperationsResult {
        home.createNote(
            id: noteId,
            title: "test \(noteId)",
            summary: "test note \(noteId)",
            tags: [tag] + extraTags,
            content: "# \(noteId)\n\nbody for \(noteId)\n"
        )
    }
    
    func noteCount(prefix: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM notes WHERE id = ? OR id GLOB ?",
                arguments: [prefix, prefix + ".*"]
            ) ?? 0
        }
    }
    
    func tags(of noteId: String) throws -> Set<String> {
        try home.read { database in
            Set(try String.fetchAll(
                database,
                sql: "SELECT tag FROM tags WHERE note_id = ?",
                arguments: [noteId]
            ))
        }
    }
    
    func tagUseCount(_ tag: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM tags WHERE tag = ?", arguments: [tag]) ?? 0
        }
    }
    
    func vocabularyContains(_ tag: String) throws -> Bool {
        try home.read { database in
            try Int.fetchOne(database, sql: "SELECT 1 FROM tag_vocab WHERE tag = ?", arguments: [tag]) != nil
        }
    }
    
    func canonical(ofAlias alias: String) throws -> String? {
        try home.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT canonical FROM tag_aliases WHERE alias = ?",
                arguments: [alias]
            )
        }
    }
    
    func frontmatterTags(of noteId: String) throws -> [String] {
        let text = try home.bodyText(of: noteId)
        let (fields, _) = try frontmatter.parse(text)
        
        return fields.tags
    }
    
    // MARK: - Private
}
