//
//  IndexOrphanPopulationInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// An orphan is a note whose file is gone. A file that merely failed to parse is still there, and
// treating the two the same deletes rows that markdown cannot rebuild.
@Suite("IndexOrphanPopulationInvariant Tests", .serialized)
struct IndexOrphanPopulationInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private let indexer = Indexer()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a file that fails to parse is an error, not an orphan — its row and usage survive")
    func incrementalParseFailureDoesNotOrphanTheNote() throws {
        // Given
        home.createNote(id: "opx", content: "## A\nbody\n")
        
        try breakFrontmatter(at: try home.indexedPath(of: "opx"))
        
        // When
        let result = try indexer.buildLocked(home.database(), rebuild: false)
        
        // Then
        let survived = try home.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes WHERE id='opx'") ?? 0,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM note_usage WHERE note_id='opx'") ?? 0
            )
        }
        
        #expect(result.orphans == 0, "a parse-failed file was counted as an orphan")
        #expect(result.errors.contains { error in error.contains("opx") },
            "a parse failure must surface in errors")
        #expect(survived == (1, 1),
            "the parse failure cascaded into Notes.delete — non-recoverable state was lost")
    }
    
    @Test("a rebuild aborts when any file fails to parse rather than committing a lossy snapshot")
    func rebuildAbortsWhenAnyFileFailsParse() throws {
        // Given
        home.createNote(id: "rbx-ok", content: "## A\nbody\n")
        home.createNote(id: "rbx-bad", content: "## A\nbody\n")
        
        try breakFrontmatter(at: try home.indexedPath(of: "rbx-bad"))
        
        // When
        #expect(throws: Error.self, "rebuild must fail loud instead of committing a lossy snapshot") {
            try indexer.buildLocked(home.database(), rebuild: true)
        }
        
        // Then
        let counts = try home.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes") ?? 0,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM note_usage") ?? 0
            )
        }
        
        #expect(counts == (2, 2), "an aborted rebuild must leave the database untouched")
    }
    
    @Test("a file that both moved and broke defers the orphan verdict — its old path is not a deletion")
    func movedAndBrokenFileDefersOrphanDeletion() throws {
        // Given
        home.createNote(id: "mvb", content: "## A\nbody\n")
        
        let destination = try move(id: "mvb", to: "skill/mvb.md")
        
        try breakFrontmatter(at: destination)
        
        // When
        let result = try indexer.buildLocked(home.database(), rebuild: false)
        
        // Then
        let rows = try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes WHERE id='mvb'") ?? -1
        }
        
        #expect(result.orphans == 0, "the old path of a moved-and-broken file was judged a deletion")
        #expect(rows == 1, "a live note was deleted while its file had merely failed to parse")
    }
    
    // Moving a file *is* re-addressing it — the location is the id, so there is
    // no second copy of the address to disagree with. The note at the old
    // address is gone and the note at the new one is there.
    @Test("moving a file re-addresses the note — old address out, new address in")
    func movingAFileReAddressesTheNote() throws {
        // Given
        home.createNote(id: "mvx", content: "## A\nbody\n")
        
        _ = try move(id: "mvx", to: "skill/mvx.md")
        
        // When
        _ = try indexer.buildLocked(home.database(), rebuild: false)
        
        // Then
        let ids = try home.read { database in
            try String.fetchAll(database, sql: "SELECT id FROM notes ORDER BY id")
        }
        let (ok, messages) = try indexer.check(home.database(), level: .l2)
        
        #expect(!ids.contains("mvx"), "the old address still has a row: \(ids)")
        #expect(ids.contains("skill.mvx"), "the new address has no row: \(ids)")
        #expect(ok, "\(messages)")
    }
    
    @Test("a genuinely removed file is still deleted as an orphan")
    func deletedFileIsStillDeletedAsOrphan() throws {
        // Given
        home.createNote(id: "gone", content: "## A\nbody\n")
        
        try FileManager.default.removeItem(at: try home.indexedPath(of: "gone"))
        
        // When
        let result = try indexer.buildLocked(home.database(), rebuild: false)
        
        // Then
        let rows = try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes WHERE id='gone'") ?? -1
        }
        
        #expect(result.orphans == 1)
        #expect(rows == 0, "a true orphan — file removed — must still be deleted")
    }
    
    // MARK: - Private
    
    private func breakFrontmatter(at url: URL) throws {
        try "---\nid: broken\ntitle: [unclosed\n".write(to: url, atomically: true, encoding: .utf8)
    }
    
    @discardableResult
    private func move(id: String, to relativePath: String) throws -> URL {
        let source = try home.indexedPath(of: id)
        let destination = Paths.cortexRoot.appendingPathComponent(relativePath)
        
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: source, to: destination)
        
        return destination
    }
}
