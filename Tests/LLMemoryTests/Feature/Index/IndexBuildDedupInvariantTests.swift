//
//  IndexBuildDedupInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("IndexBuildDedupInvariant Tests", .serialized)
struct IndexBuildDedupInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    // Two files are two locations, and a location is an id — so a copy of a note
    // is simply another note, not a contested id. The gate that used to refuse
    // duplicates has nothing left to refuse.
    @Test("a copied file is its own note, addressed by where the copy sits")
    func aCopyIsAnotherNoteNotADuplicate() throws {
        // Given
        home.createNote(id: "dupx", content: "## A\nbody\n")
        
        let original = try home.indexedPath(of: "dupx")
        let copyURL = home.url.appendingPathComponent("cortex/elsewhere/dupx.md")
        
        try FileManager.default.createDirectory(
            at: copyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: original, to: copyURL)
        
        // When
        let result = try Indexer.buildLocked(home.database(), rebuild: false)
        
        // Then
        let ids = try home.read { database in
            try String.fetchAll(database, sql: "SELECT id FROM notes ORDER BY id")
        }
        
        #expect(result.errors.isEmpty, "\(result.errors)")
        #expect(ids.contains("dupx") && ids.contains("elsewhere.dupx"), "\(ids)")
    }
    
    @Test("a rebuild wires a reference even when the referring note is scanned before its target")
    func rebuildWiresForwardReferenceRegardlessOfScanOrder() throws {
        // Given
        home.createNote(id: "idx-src", content: "## A\nsee `idx-dst` for detail\n")
        home.createNote(id: "idx-dst", content: "## A\nthe target\n")
        
        let source = try pendingNote(at: try home.indexedPath(of: "idx-src"))
        let destination = try pendingNote(at: try home.indexedPath(of: "idx-dst"))
        
        // When
        _ = try home.database().write { database in
            try Indexer.reconcile(
                database,
                pending: [source, destination],
                scannedRels: [source.rel, destination.rel],
                rebuild: true,
                now: home.now
            )
        }
        
        // Then
        let references = try home.read { database in
            Set(try String.fetchAll(
                database,
                sql: "SELECT dst FROM note_links WHERE src='idx-src' AND kind='reference'"
            ))
        }
        
        #expect(references.contains("idx-dst"),
            "the rebuild dropped a forward reference (source scanned first) — got \(references)")
    }
    
    @Test("an edit inside the same second is reindexed — content decides, not the modification time")
    func sameSecondEditIsReindexed() throws {
        // Given
        home.createNote(id: "hashx", content: "## A\noriginal body\n")
        
        let file = try home.indexedPath(of: "hashx")
        let fileManager = FileManager.default
        let frozen = try fileManager.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        let text = try String(contentsOf: file, encoding: .utf8)
        
        // When — same mtime, different body: the fast path would call this unchanged.
        try text.replacingOccurrences(of: "original body", with: "edited body")
            .write(to: file, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.modificationDate: frozen as Any], ofItemAtPath: file.path)
        
        let result = try Indexer.buildLocked(home.database(), rebuild: false)
        
        // Then
        let indexedRows = try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM notes_fts WHERE id = 'hashx' AND body LIKE '%edited body%'"
            ) ?? 0
        }
        
        #expect(result.changed == 1, "same mtime, different content must still reindex — changed=\(result.changed)")
        #expect(indexedRows >= 1, "notes_fts must carry the new body")
    }
    
    @Test("content drift that never reached the index is reported at level 2")
    func contentDriftIsReportedAtLevelTwo() throws {
        // Given
        home.createNote(id: "hashx", content: "## A\noriginal body\n")
        
        let file = try home.indexedPath(of: "hashx")
        let fileManager = FileManager.default
        let frozen = try fileManager.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        let text = try String(contentsOf: file, encoding: .utf8)
        
        // When — edited on disk, never rebuilt.
        try text.replacingOccurrences(of: "original body", with: "third body")
            .write(to: file, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.modificationDate: frozen as Any], ofItemAtPath: file.path)
        
        let (passed, messages) = try Indexer.check(home.database(), level: .l2)
        
        // Then
        #expect(!passed)
        #expect(messages.contains { message in
            message.contains("stale-content") && message.contains("hashx")
        }, "level 2 must name the drifted note — got \(messages)")
    }
    
    // MARK: - Private
    
    private func pendingNote(at url: URL) throws -> Indexer.PendingNote {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let relativePath = resolved.path.replacingOccurrences(of: Paths.brainRoot.path + "/", with: "")
        let text = try String(contentsOf: resolved, encoding: .utf8)
        let (fields, body) = try Frontmatter.parse(text)
        
        return Indexer.PendingNote(
            file: resolved,
            rel: relativePath,
            raw: text,
            contentHash: Notes.contentHash(text),
            fields: fields,
            body: body
        )
    }
}
