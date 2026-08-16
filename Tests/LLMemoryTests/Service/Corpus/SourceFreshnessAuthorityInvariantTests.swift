//
//  SourceFreshnessAuthorityInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("SourceFreshnessAuthorityInvariant Tests", .serialized)
struct SourceFreshnessAuthorityInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    private static func writeNote(_ layout: BrainLayout, _ id: String, sources: [URL]) throws -> URL {
        let directory = layout.notes
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let path = directory.appendingPathComponent("\(id).md")
        let list = sources.map { source in "\"\(source.path)\"" }.joined(separator: ", ")
        
        try """
        ---
        id: \(id)
        title: t
        priority: lazy
        tags: [flow]
        summary: s
        source: [\(list)]
        ---

        # body
        """.write(to: path, atomically: true, encoding: .utf8)
        
        return path
    }
    
    private static func mtime(_ url: URL) throws -> Date {
        try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as! Date
    }
    
    private static func setMtime(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
    
    @Test("content decides freshness, not the modification time — an edit under a restored timestamp is still detected")
    func contentChangeUnderARestoredMtimeIsDetected() throws {
        // Given
        let source = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: source, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote(home.layout, "fresh-1", sources: [source])
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try ReindexNoteFileTransaction(noteId: try home.brain.requireNoteId(of: path), path: path).perform(db) }
        
        let baselineMtime = try Self.mtime(source)
        
        // When
        try "beta — different bytes, same timestamp".write(to: source, atomically: true, encoding: .utf8)
        try Self.setMtime(source, baselineMtime)
        
        // Then
        #expect(abs(try Self.mtime(source).timeIntervalSince(baselineMtime)) < 0.000_001,
            "probe setup: mtime was not restored")
        
        let result = try queue.write { db in try SourceVerifier().verifyAll(GRDBScope(db), home.brain) }
        
        #expect(result.stillFresh == 0, "verify declared a note fresh without looking at its content")
        #expect(result.becameStale == 1, "content drift under a restored mtime went undetected")
        
        let stale = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_stale FROM note_source WHERE note_id = 'fresh-1'") ?? -1
        }
        
        #expect(stale == 1, "source_stale not set — got \(stale)")
    }
    
    @Test("a repeated check does not latch detection off — the verdict is recomputed each time")
    func detectionIsNotLatchedOffByARepeatedPass() throws {
        // Given
        let source = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: source, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote(home.layout, "fresh-2", sources: [source])
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try ReindexNoteFileTransaction(noteId: try home.brain.requireNoteId(of: path), path: path).perform(db) }
        
        let baselineMtime = try Self.mtime(source)
        
        _ = try queue.write { db in try SourceVerifier().verifyAll(GRDBScope(db), home.brain) }
        
        try "beta".write(to: source, atomically: true, encoding: .utf8)
        try Self.setMtime(source, baselineMtime)
        
        _ = try queue.write { db in try SourceVerifier().verifyAll(GRDBScope(db), home.brain) }
        
        // When
        let stale = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_stale FROM note_source WHERE note_id = 'fresh-2'") ?? -1
        }
        
        // Then
        #expect(stale == 1, "drift stayed invisible after an earlier clean pass — got \(stale)")
    }
    
    @Test("restoring the original content makes the note fresh again")
    func restoringTheOriginalContentRecoversFreshness() throws {
        // Given
        let source = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: source, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote(home.layout, "fresh-3", sources: [source])
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try ReindexNoteFileTransaction(noteId: try home.brain.requireNoteId(of: path), path: path).perform(db) }
        try "beta".write(to: source, atomically: true, encoding: .utf8)
        
        // When
        let drifted = try queue.write { db in try SourceVerifier().verifyAll(GRDBScope(db), home.brain) }
        
        // Then
        #expect(drifted.becameStale == 1)
        
        try "alpha".write(to: source, atomically: true, encoding: .utf8)
        
        let recovered = try queue.write { db in try SourceVerifier().verifyAll(GRDBScope(db), home.brain) }
        
        #expect(recovered.recovered == 1, "restoring the original content did not clear source_stale")
    }
    
    @Test("losing one of several declared sources is still a change")
    func partialSourceDeletionIsStillDetected() throws {
        // Given
        let first = home.url.appendingPathComponent("s1.txt")
        let second = home.url.appendingPathComponent("s2.txt")
        
        try "alpha".write(to: first, atomically: true, encoding: .utf8)
        try "beta".write(to: second, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote(home.layout, "fresh-4", sources: [first, second])
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try ReindexNoteFileTransaction(noteId: try home.brain.requireNoteId(of: path), path: path).perform(db) }
        try FileManager.default.removeItem(at: second)
        
        _ = try queue.write { db in try SourceVerifier().verifyAll(GRDBScope(db), home.brain) }
        
        // When
        let stale = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_stale FROM note_source WHERE note_id = 'fresh-4'") ?? -1
        }
        
        // Then
        #expect(stale == 1, "partial source deletion stayed fresh — got \(stale)")
    }
}
