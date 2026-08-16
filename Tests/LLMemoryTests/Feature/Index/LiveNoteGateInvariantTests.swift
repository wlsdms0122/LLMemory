//
//  LiveNoteGateInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("LiveNoteGateInvariant Tests", .serialized)
struct LiveNoteGateInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private let indexer = Indexer()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("reindexing a trashed file is refused — deletion must not be undone by a rebuild")
    func reindexingATrashedFileIsRefused() throws {
        // Given
        let trashed = try trashNote(id: "live-1")
        
        // When
        #expect(throws: (any Error).self, "a trashed file was reindexed back into live notes") {
            _ = try home.database().write { database in try ReindexNoteFileTransaction(path: trashed).perform(database, home.brain) }
        }
        
        // Then
        #expect(try noteRows(id: "live-1") == 0, "the trashed note came back as a live row")
        #expect(try indexedRows(id: "live-1") == 0, "the trashed note came back in FTS")
    }
    
    // Sync by fixture contract — MemoryHome holds its exclusion for the
    // fixture's lifetime, so no test may suspend under it (an await here
    // starves the pool and hangs the run). The locked write goes through
    // writeLock; the async storage.run + exit-code surface is covered
    // end-to-end by IndexCommandTests against the real binary.
    @Test("index reindex reports failure for a trashed path instead of quietly doing nothing")
    func indexReindexReportsFailureForATrashedPath() throws {
        // Given
        let trashed = try trashNote(id: "live-2")

        // When
        let outcomes = try home.write { db in
            try indexer.reindexFiles(db, home.brain, filePaths: [trashed.path])
        }
        let failed = outcomes.contains { outcome in
            if case .failure = outcome.result { return true }

            return false
        }

        // Then
        #expect(failed, "index reindex reported success for a trashed path")
        #expect(try noteRows(id: "live-2") == 0, "the trashed note came back as a live row")
    }
    
    @Test("restore is the one way back — the op still brings a trashed note into live rows")
    func restoreOpStillBringsATrashedNoteBack() throws {
        // Given
        _ = try trashNote(id: "live-4")
        
        // When
        let restored = home.apply(["op": "restore", "id": "live-4"])
        
        // Then
        #expect(restored.status == "ok", "restore failed: \(restored.error)")
        #expect(try noteRows(id: "live-4") == 1, "restore did not bring the note back")
    }
    
    // A file the gate admits but the walk never reaches is reindexable by path and orphaned by the
    // next build — the two must agree on exactly the same set.
    @Test("the live-note gate and the directory walk admit the same files")
    func everyPredicateAdmittedFileIsDiscoverableByTheWalk() throws {
        // Given
        _ = try trashNote(id: "live-3")
        
        let cortex = home.layout.notes
        let fileManager = FileManager.default
        
        try fileManager.createDirectory(
            at: cortex.appendingPathComponent("flow/.hidden"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: cortex.appendingPathComponent("tech"),
            withIntermediateDirectories: true
        )
        
        for (relativePath, text) in [
            ("flow/README.md", "# readme"),
            ("flow/_draft.md", "# draft"),
            ("flow/notes.txt", "not markdown"),
            ("flow/.hidden/h.md", "# hidden"),
            ("tech/plain.md", "# plain")
        ] {
            try text.write(to: cortex.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
        }
        
        // When
        let walked = Set(home.layout.scanNotes().map { url in url.standardized.path })
        let enumerator = fileManager.enumerator(at: cortex, includingPropertiesForKeys: [.isRegularFileKey])!
        
        // Then
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            
            let resolved = url.standardized
            
            guard home.layout.liveNoteRejection(of: resolved) == nil else { continue }
            
            #expect(walked.contains(resolved.path),
                "the gate admits a file the walk never discovers: \(resolved.path)")
        }
        
        // No file name under cortex/ is reserved — only a non-note extension and
        // the trash are refused, so README.md and _draft.md are ordinary notes.
        for relativePath in ["flow/notes.txt", ".trash/live-3.md"] {
            #expect(home.layout.liveNoteRejection(of: cortex.appendingPathComponent(relativePath)) != nil,
                "the gate admits \(relativePath)")
        }
        
        for relativePath in ["flow/README.md", "flow/_draft.md"] {
            #expect(home.layout.liveNoteRejection(of: cortex.appendingPathComponent(relativePath)) == nil,
                "the gate still treats \(relativePath) as reserved")
        }
        
        #expect(home.layout.liveNoteRejection(of: cortex.appendingPathComponent("tech/plain.md")) == nil,
            "the gate refuses an ordinary note")
    }
    
    // MARK: - Private
    @discardableResult
    private func trashNote(id: String) throws -> URL {
        let created = home.createNote(id: id, content: "# body", fields: [:])
        
        #expect(created.status == "ok", "setup: create failed — \(created.error)")
        
        let deleted = home.apply(["op": "delete_note", "id": id, "reason": "test"])
        
        #expect(deleted.status == "ok", "setup: delete failed — \(deleted.error)")
        
        let trashed = home.layout.trash.appendingPathComponent("\(id).md")
        
        guard FileManager.default.fileExists(atPath: trashed.path) else {
            throw TestFailure("setup: no trashed file at \(trashed.path)")
        }
        
        return trashed
    }
    
    private func noteRows(id: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes WHERE id = ?", arguments: [id]) ?? 0
        }
    }
    
    private func indexedRows(id: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes_fts WHERE id = ?", arguments: [id]) ?? 0
        }
    }
}
