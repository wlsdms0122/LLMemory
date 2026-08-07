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

// An axis is a row, a set of note paths and a tag on every note filed under it. Renaming one has to
// move all three together, or the corpus disagrees with itself.
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
    @Test("an axis description can be set on an axis that exists")
    func setAxisDescriptionUpdates() throws {
        // Given
        lifecycle.create("tdb-x1", axis: "tdbaxis")
        
        // When
        let result = home.apply([
            "op": "set_axis_description", "axis": "tdbaxis", "description": "what this axis means"
        ])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try lifecycle.axisDescription(of: "tdbaxis") == "what this axis means")
    }
    
    @Test("describing an axis that does not exist is refused rather than creating one")
    func setAxisDescriptionUnknownRejected() {
        // When
        let result = home.apply([
            "op": "set_axis_description", "axis": "nope-axis-xyz", "description": "x"
        ])
        
        // Then
        #expect(result.status != "ok")
    }
    
    @Test("a blank description is refused — an axis with no meaning stated is not described")
    func setAxisDescriptionEmptyRejected() {
        // Given
        lifecycle.create("tdb-x2", axis: "tdbaxis")
        
        // When
        let result = home.apply(["op": "set_axis_description", "axis": "tdbaxis", "description": "   "])
        
        // Then
        #expect(result.status != "ok")
    }
    
    @Test("renaming an axis moves its description, its rows, its files and its tag together")
    func renameAxisMovesFilesAndDB() throws {
        // Given
        lifecycle.create("tdb-ra1", axis: "tdbaxis", axisDescription: "the original meaning", extraTags: ["alpha"])
        lifecycle.create("tdb-ra2", axis: "tdbaxis", extraTags: ["beta"])
        
        // When
        let result = home.apply(["op": "rename_axis", "from_axis": "tdbaxis", "to_axis": "tdbaxis-renamed"])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try lifecycle.axisDescription(of: "tdbaxis-renamed") == "the original meaning")
        #expect(try lifecycle.noteCount(axis: "tdbaxis-renamed") == 2)
        
        for (noteId, extraTag) in [("tdb-ra1", "alpha"), ("tdb-ra2", "beta")] {
            let file = try home.indexedPath(of: noteId)
            let tags = try lifecycle.tags(of: noteId)
            
            #expect(file.path.hasSuffix("tdbaxis-renamed/\(noteId).md"), "the file did not move")
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(tags.contains("tdbaxis-renamed"))
            #expect(!tags.contains("tdbaxis"), "the old axis tag stayed behind")
            #expect(tags.contains(extraTag), "an unrelated tag must survive the rename")
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
    
    @Test("renaming onto an axis that already exists is refused rather than merging the two")
    func renameToExistingAxisRejected() {
        // Given
        lifecycle.create("tdb-re1", axis: "tdbaxis")
        
        // When
        let result = home.apply(["op": "rename_axis", "from_axis": "tdbaxis", "to_axis": "persona"])
        
        // Then
        #expect(result.status != "ok")
    }
    
    @Test("renaming an axis carries the old axis-tag's inbound aliases and retires the unused row")
    func renameAxisRetiresOldAxisTag() throws {
        // Given
        lifecycle.create("tdb-ax1", axis: "axgone", extraTags: ["legacy"])
        
        #expect(home.apply([
            "op": "rename_tag", "from_tag": "legacy", "to_tag": "axgone", "add_alias": true
        ]).status == "ok")
        
        // When
        let renamed = home.apply(["op": "rename_axis", "from_axis": "axgone", "to_axis": "axnew"])
        
        // Then
        #expect(renamed.status == "ok", "\(renamed.error)")
        #expect(try lifecycle.canonical(ofAlias: "legacy") == "axnew",
            "an inbound alias must follow the axis tag it pointed at")
        #expect(try !lifecycle.vocabularyContains("axgone"), "the unused old axis tag must be retired")
        
        // When — renaming onto a spelling that is an alias of something else.
        lifecycle.create("tdb-ax3", axis: "axsrc")
        
        let refused = home.apply(["op": "rename_axis", "from_axis": "axsrc", "to_axis": "legacy"])
        
        // Then
        #expect(refused.status != "ok")
        #expect(refused.error.contains("alias"), "the reason must reach the caller: \(refused.error)")
    }
    
    @Test("an old axis-tag still used elsewhere survives the rename — retiring it is rename_tag's call")
    func renameAxisKeepsInUseAxisTag() throws {
        // Given
        lifecycle.create("tdb-bx1", axis: "bxgone")
        lifecycle.create("tdb-bx2", axis: "bxother", extraTags: ["bxgone"])
        
        // When
        let renamed = home.apply(["op": "rename_axis", "from_axis": "bxgone", "to_axis": "bxnew"])
        
        // Then
        #expect(renamed.status == "ok", "\(renamed.error)")
        #expect(try lifecycle.vocabularyContains("bxgone"), "a tag still in use outside the axis must survive")
        #expect(try lifecycle.tags(of: "tdb-bx2").contains("bxgone"))
    }
}
