//
//  PathIdInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/13/26.
//

import Testing
import Foundation
@testable import LLMemory

// The id is the address. Everything here holds that claim to its two
// consequences: the path is a pure function of the id, and the function is
// invertible — so nothing about a note's whereabouts needs storing, and nothing
// stored can disagree with it.
@Suite("PathId Invariant Tests", .serialized)
struct PathIdInvariantTests {
    // MARK: - Property
    private let home: MemoryHome

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("a dot in the id is a directory separator, and the last label is the file")
    func idSpellsThePath() {
        #expect(Paths.relativeFile(forId: "principles") == "cortex/principles.md")
        #expect(Paths.relativeFile(forId: "a.b") == "cortex/a/b.md")
        #expect(Paths.relativeFile(forId: "journal.2026.08.bkios-545")
            == "cortex/journal/2026/08/bkios-545.md")
    }

    @Test("reading the address back off the file returns the id it was built from")
    func pathAndIdAreInverses() {
        for id in ["principles", "a.b", "a.b.c.d", "journal.2026.08.bkios-545"] {
            #expect(Paths.id(ofFile: Paths.file(forId: id)) == id, "round trip broke for \(id)")
        }
    }

    @Test("only a dot-joined kebab id is an address — everything else is refused")
    func idSyntaxIsLabelsJoinedByDots() {
        for accepted in ["a", "a-b", "a.b", "a.b-c.d", "2026", "a.2026.08.x"] {
            #expect(Paths.idRegex.firstMatch(
                in: accepted,
                range: NSRange(location: 0, length: (accepted as NSString).length)
            ) != nil, "refused a valid address: \(accepted)")
        }

        for refused in ["", ".a", "a.", "a..b", "-a", "a.-b", "A.b", "a b", "a_b", "a/b"] {
            #expect(Paths.idRegex.firstMatch(
                in: refused,
                range: NSRange(location: 0, length: (refused as NSString).length)
            ) == nil, "admitted an invalid address: \(refused)")
        }
    }

    @Test("a note and its children coexist — a name is a file and a directory at once")
    func aNodeIsBothRecordAndParent() throws {
        // Given
        #expect(home.createNote(id: "a.b", content: "## A\nparent body\n").status == "ok")
        #expect(home.createNote(id: "a.b.c", content: "## A\nchild body\n").status == "ok")

        // Then
        let parent = home.url.appendingPathComponent("cortex/a/b.md")
        let child = home.url.appendingPathComponent("cortex/a/b/c.md")

        #expect(FileManager.default.fileExists(atPath: parent.path))
        #expect(FileManager.default.fileExists(atPath: child.path))

        let (ok, messages) = try Indexer.check(home.database(), level: .l2)

        #expect(ok, "\(messages)")
    }

    @Test("the tree counts everything below a prefix, one level at a time")
    func treeCountsBelowEachBranch() throws {
        // Given
        for id in ["a.b", "a.b.c", "a.d", "e"] {
            #expect(home.createNote(id: id, content: "## A\nbody\n").status == "ok")
        }

        // When
        let top = try home.read { database in try FetchTreeTransaction().perform(database) }
        let under = try home.read { database in
            try FetchTreeTransaction(prefix: "a").perform(database)
        }

        // Then
        #expect(top.map(\.prefix) == ["a", "e"])
        #expect(top.first { row in row.prefix == "a" }?.notes == 3,
            "a branch counts every note below it, not just its immediate children")
        #expect(under.map(\.prefix) == ["a.b", "a.d"])
        #expect(under.first { row in row.prefix == "a.b" }?.notes == 2,
            "a prefix that is itself a note counts alongside its children")
    }

    @Test("the frontmatter id decides where the file goes, not the other way round")
    func createPutsTheFileWhereTheIdSays() throws {
        // Given
        #expect(home.createNote(id: "x.y.z", content: "## A\nbody\n").status == "ok")

        // Then
        let file = home.url.appendingPathComponent("cortex/x/y/z.md")
        let (document, _) = try Frontmatter.parse(try String(contentsOf: file, encoding: .utf8))

        #expect(document.id == "x.y.z")
    }
}
