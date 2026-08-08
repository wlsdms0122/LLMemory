//
//  NoteLifecycle.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import GRDB
@testable import LLMemory

// Reads the catalog rows that axis and tag lifecycle work moves around, and creates the notes those
// tests need. Kept apart from the tests so the assertions read as claims rather than as SQL.
struct NoteLifecycle {
    // MARK: - Property
    private let home: any BrainHome
    
    // MARK: - Initializer
    init(_ home: any BrainHome) {
        self.home = home
    }
    
    // MARK: - Public
    @discardableResult
    func create(
        _ noteId: String,
        axis: String,
        axisDescription: String = "(test axis)",
        extraTags: [String] = []
    ) -> OpsTransaction.Result {
        home.createNote(
            id: noteId,
            axis: axis,
            title: "test \(noteId)",
            summary: "test note \(noteId)",
            tags: [axis] + extraTags,
            content: "# \(noteId)\n\nbody for \(noteId)\n",
            fields: ["axis_description": axisDescription]
        )
    }
    
    func axisDescription(of axis: String) throws -> String? {
        try home.read { database in
            try String.fetchOne(
                database,
                sql: "SELECT description FROM axes WHERE axis = ?",
                arguments: [axis]
            )
        }
    }
    
    func axisExists(_ axis: String) throws -> Bool {
        try home.read { database in
            try Int.fetchOne(database, sql: "SELECT 1 FROM axes WHERE axis = ?", arguments: [axis]) != nil
        }
    }
    
    func noteCount(axis: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM notes WHERE axis = ?",
                arguments: [axis]
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
        let (fields, _) = try Frontmatter.parse(text)
        
        return fields.tags
    }
    
    // MARK: - Private
}
