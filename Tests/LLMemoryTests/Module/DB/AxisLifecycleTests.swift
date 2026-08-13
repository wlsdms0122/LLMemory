//
//  AxisLifecycleTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// An axis is a row and a set of note paths — the directory a note's file lives in, nothing more.
// Classification is what tags are for, so a rename moves files and rows and leaves tags alone.
@Suite("AxisLifecycle Tests", .serialized)
struct AxisLifecycleTests {
    // MARK: - Property
    private let home: MemoryHome
    private let lifecycle: NoteLifecycle
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
        lifecycle = NoteLifecycle(home)
    }
    
    // MARK: - Test
    @Test("renaming an axis moves its rows and its files together, and leaves tags alone")
    func renameAxisMovesFilesAndDB() throws {
        // Given
        lifecycle.create("tdb-ra1", axis: "tdbaxis", extraTags: ["alpha"])
        lifecycle.create("tdb-ra2", axis: "tdbaxis", extraTags: ["beta"])
        
        // When
        let result = home.apply(["op": "rename_axis", "from_axis": "tdbaxis", "to_axis": "tdbaxis-renamed"])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try lifecycle.noteCount(axis: "tdbaxis-renamed") == 2)
        
        for (noteId, extraTag) in [("tdb-ra1", "alpha"), ("tdb-ra2", "beta")] {
            let file = try home.indexedPath(of: noteId)
            let tags = try lifecycle.tags(of: noteId)
            
            #expect(file.path.hasSuffix("tdbaxis-renamed/\(noteId).md"), "the file did not move")
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(tags.contains(extraTag), "an unrelated tag must survive the rename")
            #expect(tags.contains("tdbaxis"),
                "a tag is classification — moving the drawer must not rewrite it")
        }
    }
    
    @Test("any axis can be renamed — no axis is shipped vocabulary the brain cannot redefine")
    func renameAnyAxisAllowed() throws {
        // Given
        lifecycle.create("tdb-rs1", axis: "tech")

        // When
        let result = home.apply(["op": "rename_axis", "from_axis": "tech", "to_axis": "technology"])

        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try !lifecycle.axisExists("tech"))
        #expect(try lifecycle.noteCount(axis: "technology") == 1)
    }
    
    @Test("every op that names an axis answers the same way — a directory is made on demand")
    func anUnknownAxisIsCreatedByWhicheverOpNamesIt() throws {
        // Given
        lifecycle.create("tdb-g1", axis: "gateaxis")
        lifecycle.create("tdb-g2", axis: "gateaxis")
        
        #expect(home.apply([
            "op": "patch_section", "id": "tdb-g2", "section": "# tdb-g2",
            "action": "append", "content": "## Left\nl\n\n## Right\nr\n"
        ]).status == "ok")
        
        // Then — create already made 'gateaxis'; migrate and split may name a fresh one too
        #expect(home.apply([
            "op": "migrate_note", "id": "tdb-g1", "new_axis": "gate-migrated"
        ]).status == "ok")
        #expect(try lifecycle.noteCount(axis: "gate-migrated") == 1)
        
        let split = home.apply([
            "op": "split_note", "from_id": "tdb-g2",
            "into": [
                [
                    "id": "tdb-g2-a", "axis": "gate-split", "title": "A",
                    "tags": ["alpha"], "summary": "a", "sections": ["# tdb-g2 > ## Left"]
                ],
                [
                    "id": "tdb-g2-b", "axis": "gate-split", "title": "B",
                    "tags": ["beta"], "summary": "b", "sections": ["# tdb-g2 > ## Right"]
                ]
            ]
        ])
        
        #expect(split.status == "ok", "\(split.error)")
        #expect(try lifecycle.noteCount(axis: "gate-split") == 2)
        
        // And all three refuse the same malformed name
        for operation in [
            ["op": "create_note", "id": "tdb-g3", "axis": "Bad Axis", "title": "t",
             "tags": ["x"], "summary": "s", "content": "# t\n"] as [String: Any],
            ["op": "migrate_note", "id": "tdb-g1", "new_axis": "Bad Axis"]
        ] {
            #expect(home.apply(operation).status != "ok", "\(operation)")
        }
    }
    
    @Test("renaming onto an axis that already exists is refused rather than merging the two")
    func renameToExistingAxisRejected() {
        // Given
        lifecycle.create("tdb-re1", axis: "tdbaxis")
        
        // When
        let result = home.apply(["op": "rename_axis", "from_axis": "tdbaxis", "to_axis": "persona"])
        
        // Then
        #expect(result.status != "ok")
    }
    
    @Test("an axis may be renamed onto a name the tag vocabulary already uses — the two do not collide")
    func renameAxisOntoExistingTagAllowed() throws {
        // Given
        lifecycle.create("tdb-ax1", axis: "axgone", extraTags: ["legacy"])
        
        // When
        let renamed = home.apply(["op": "rename_axis", "from_axis": "axgone", "to_axis": "legacy"])
        
        // Then
        #expect(renamed.status == "ok", "\(renamed.error)")
        #expect(try lifecycle.noteCount(axis: "legacy") == 1)
        #expect(try lifecycle.tags(of: "tdb-ax1").contains("legacy"),
            "the note keeps the tag it always had, for its own reasons")
    }
}
