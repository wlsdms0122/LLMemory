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

    // A branch with no note at its own address is ordinary, not broken — every
    // old axis was exactly that. So moving a note is moving a note: `a.b.c` is a
    // separate note with its own address and nothing about it changes.
    @Test("re-addressing a node leaves the notes under its old address alone")
    func migrateDoesNotTouchNotesUnderTheOldAddress() throws {
        // Given
        #expect(home.createNote(id: "p.q", content: "## A\nparent\n").status == "ok")
        #expect(home.createNote(id: "p.q.r", content: "## A\nchild\n").status == "ok")

        // When
        let result = home.apply(["op": "migrate_note", "id": "p.q", "new_id": "p.moved"])

        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(FileManager.default.fileExists(
            atPath: home.url.appendingPathComponent("cortex/p/q/r.md").path
        ), "the note under the old address must be untouched")

        let rows = try home.read { database in try FetchTreeTransaction(prefix: "p").perform(database) }

        #expect(Set(rows.map(\.prefix)) == ["p.q", "p.moved"])
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

    // The stats for a branch include the note sitting at the branch itself, so
    // the tree rows have to reach that total — otherwise the two fields of one
    // `structure --prefix` response disagree and neither can be checked.
    @Test("a branch's rows add up to the branch's stats, including the node itself")
    func treeRowsReconcileWithPrefixStats() throws {
        // Given — a note at `m` and notes under it.
        for id in ["m", "m.n", "m.n.o"] {
            #expect(home.createNote(id: id, content: "## A\nbody\n").status == "ok")
        }

        // When
        let rows = try home.read { database in
            try FetchTreeTransaction(prefix: "m").perform(database)
        }
        let stats = try home.read { database in
            try PrefixStatsTransaction(prefix: "m").perform(database)
        }

        // Then
        #expect(rows.map(\.notes).reduce(0, +) == stats.total, "\(rows.map(\.prefix)) vs \(stats.total)")
        #expect(rows.contains { row in row.prefix == "m" && row.notes == 1 },
            "the note at the prefix needs a row of its own: \(rows.map(\.prefix))")
    }

    // The address is written once, as the file's location. A note that also
    // spelled its id in frontmatter would be carrying a second copy of the same
    // fact, and two copies of a fact are a disagreement waiting to happen.
    @Test("a note declares no id — the file's location is the only place it lives")
    func theFileLocationIsTheOnlyAddress() throws {
        // Given
        #expect(home.createNote(id: "x.y.z", content: "## A\nbody\n").status == "ok")

        // When
        let file = home.url.appendingPathComponent("cortex/x/y/z.md")
        let text = try String(contentsOf: file, encoding: .utf8)

        // Then
        #expect(!text.contains("\nid:"), "the note wrote its address down a second time")
        #expect(Paths.id(ofFile: file) == "x.y.z", "the location is where the id comes from")

        let indexed = try home.read { database in
            try String.fetchAll(database, sql: "SELECT id FROM notes WHERE id = 'x.y.z'")
        }

        #expect(indexed == ["x.y.z"])
    }
}
