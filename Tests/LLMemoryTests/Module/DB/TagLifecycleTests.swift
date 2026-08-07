//
//  TagLifecycleTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// A tag lives in three places at once: the vocabulary, each note's rows, and each note's frontmatter.
// Renaming one has to reach all three, and the alias trail has to stay usable afterwards.
@Suite("TagLifecycle Tests", .serialized)
struct TagLifecycleTests {
    // MARK: - Property
    private let home: MemoryHome
    private let lifecycle: NoteLifecycle
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        lifecycle = NoteLifecycle(home)
    }
    
    // MARK: - Test
    @Test("renaming a tag updates the rows, the vocabulary and every note's frontmatter")
    func renameTagUpdatesDatabaseAndFiles() throws {
        // Given
        lifecycle.create("tdb-rt1", axis: "tdbaxis", extraTags: ["tdbtag-old", "shared"])
        lifecycle.create("tdb-rt2", axis: "tdbaxis", extraTags: ["tdbtag-old"])
        
        // When
        let result = home.apply(["op": "rename_tag", "from_tag": "tdbtag-old", "to_tag": "tdbtag-new"])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try lifecycle.tagUseCount("tdbtag-old") == 0)
        #expect(try lifecycle.tagUseCount("tdbtag-new") == 2)
        #expect(try !lifecycle.vocabularyContains("tdbtag-old"))
        #expect(try lifecycle.vocabularyContains("tdbtag-new"))
        
        for noteId in ["tdb-rt1", "tdb-rt2"] {
            let tags = try lifecycle.frontmatterTags(of: noteId)
            
            #expect(!tags.contains("tdbtag-old"), "the file still spells the old tag")
            #expect(tags.contains("tdbtag-new"))
        }
    }
    
    @Test("renaming again carries the earlier alias forward, and never leaves a self-alias behind")
    func reRenamePreservesInboundAliases() throws {
        // Given
        lifecycle.create("tdb-ra1", axis: "tdbaxis", extraTags: ["tag-a"])
        
        #expect(home.apply([
            "op": "rename_tag", "from_tag": "tag-a", "to_tag": "tag-b", "add_alias": true
        ]).status == "ok")
        
        // When
        #expect(home.apply([
            "op": "rename_tag", "from_tag": "tag-b", "to_tag": "tag-c", "add_alias": true
        ]).status == "ok")
        
        // Then
        #expect(try lifecycle.canonical(ofAlias: "tag-a") == "tag-c",
            "the a→b alias must follow b→c")
        #expect(try lifecycle.canonical(ofAlias: "tag-b") == "tag-c")
        
        // When — renamed back to the original spelling.
        #expect(home.apply([
            "op": "rename_tag", "from_tag": "tag-c", "to_tag": "tag-a", "add_alias": true
        ]).status == "ok")
        
        // Then
        let selfAliases = try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM tag_aliases WHERE alias = canonical") ?? 0
        }
        
        #expect(selfAliases == 0, "a tag must not end up as an alias of itself")
    }
    
    @Test("renaming onto a spelling that already aliases something else is refused")
    func renameOntoForeignAliasRejected() {
        // Given
        lifecycle.create("tdb-fa1", axis: "tdbaxis", extraTags: ["tag-x"])
        lifecycle.create("tdb-fa2", axis: "tdbaxis", extraTags: ["tag-f"])
        
        #expect(home.apply([
            "op": "rename_tag", "from_tag": "tag-x", "to_tag": "tag-x2", "add_alias": true
        ]).status == "ok")
        
        // When
        let result = home.apply(["op": "rename_tag", "from_tag": "tag-f", "to_tag": "tag-x"])
        
        // Then
        #expect(result.status != "ok", "'tag-x' now means 'tag-x2' — got \(result.status)")
        #expect(result.error.contains("alias of"), "the reason must reach the caller: \(result.error)")
    }
    
    @Test("renaming a tag rewrites the file, so the recorded modification time follows it")
    func renameTagRefreshesFileMtime() throws {
        // Given
        lifecycle.create("tdb-rtm1", axis: "tdbaxis", extraTags: ["mtag"])
        
        let file = try home.indexedPath(of: "tdb-rtm1")
        let backdated = 1_000_000_000
        
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(backdated))],
            ofItemAtPath: file.path
        )
        try home.database().write { database in
            try database.execute(
                sql: "UPDATE notes SET file_mtime = ? WHERE id = 'tdb-rtm1'",
                arguments: [backdated]
            )
        }
        
        // When
        #expect(home.apply(["op": "rename_tag", "from_tag": "mtag", "to_tag": "mtag2"]).status == "ok")
        
        // Then
        let recorded = try home.read { database in
            try Int.fetchOne(database, sql: "SELECT file_mtime FROM notes WHERE id = 'tdb-rtm1'") ?? -1
        }
        let onDisk = Int(
            (try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? -1
        )
        
        #expect(recorded == onDisk, "the recorded time drifted from the file — recorded=\(recorded) disk=\(onDisk)")
        #expect(recorded != backdated, "the rewrite did not actually happen")
    }
    
    @Test("creating a note with an aliased tag converges the file on the canonical spelling")
    func createWithAliasTagConvergesFileToCanonical() throws {
        // Given
        lifecycle.create("tdb-nt1", axis: "tdbaxis", extraTags: ["oldspell"])
        
        #expect(home.apply([
            "op": "rename_tag", "from_tag": "oldspell", "to_tag": "newspell", "add_alias": true
        ]).status == "ok")
        
        // When — a new note is written with the retired spelling.
        lifecycle.create("tdb-nt2", axis: "tdbaxis", extraTags: ["oldspell"])
        
        // Then
        let fileTags = try lifecycle.frontmatterTags(of: "tdb-nt2")
        let rowTags = try lifecycle.tags(of: "tdb-nt2")
        
        #expect(fileTags.contains("newspell"), "the file must converge on the canonical tag — got \(fileTags)")
        #expect(!fileTags.contains("oldspell"), "the alias spelling must not persist in the file")
        #expect(rowTags.contains("newspell"))
        #expect(!rowTags.contains("oldspell"), "the rows and the file must agree")
    }
}
