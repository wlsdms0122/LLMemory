//
//  SourceGateInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("SourceGateInvariant Tests", .serialized)
struct SourceGateInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    
    private static func note(id: String, source: String) -> String {
        """
        ---
        id: \(id)
        title: t
        axis: flow
        priority: lazy
        tags: [flow]
        summary: s
        source: \(source)
        ---

        # body
        """
    }
    
    @discardableResult
    private static func writeNote(_ id: String, source: String) throws -> URL {
        let directory = Paths.notes.appendingPathComponent("flow")
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let path = directory.appendingPathComponent("\(id).md")
        
        try note(id: id, source: source).write(to: path, atomically: true, encoding: .utf8)
        
        return path
    }
    
    // 1. verify must never convert "cannot read the declaration" into "no declaration"
    @Test("a malformed declaration fails verification instead of erasing the baseline it could not read")
    func malformedSourceInFileFailsVerifyInsteadOfDeletingTheBaseline() throws {
        // Given
        let grounding = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: grounding, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote("gate-1", source: "[\"\(grounding.path)\"]")
        let queue = try DB.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: path) }
        try "alpha changed".write(to: grounding, atomically: true, encoding: .utf8)
        
        _ = try queue.write { db in try SourcesService.bulkVerify(db) }
        
        // When
        let staleBefore = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_stale FROM note_source WHERE note_id = 'gate-1'") ?? -1
        }
        
        // Then
        #expect(staleBefore == 1, "setup: expected drift to be flagged, got \(staleBefore)")
        
        try Self.note(id: "gate-1", source: "[\(grounding.path)]")
            .write(to: path, atomically: true, encoding: .utf8)
        
        let result = try queue.write { db in try SourcesService.bulkVerify(db) }
        
        #expect(result.unreadable.count == 1 && result.unreadable[0].contains("gate-1"),
            "the skip was not reported: \(result.unreadable)")
        
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT source_hash, source_stale FROM note_source WHERE note_id = 'gate-1'")
        }
        
        #expect(row != nil, "baseline row was deleted by a note whose markdown still declares a source")
        #expect(row?["source_stale"] as Int? == 1, "drift flag was laundered by the unreadable declaration")
    }
    
    @Test("an unreadable note fails verification for the same reason")
    func unreadableNoteFileFailsVerifyInsteadOfDeletingTheBaseline() throws {
        // Given
        let grounding = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: grounding, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote("gate-2", source: "[\"\(grounding.path)\"]")
        let queue = try DB.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: path) }
        try FileManager.default.removeItem(at: path)
        
        // When
        let result = try queue.write { db in try SourcesService.bulkVerify(db) }
        
        // Then
        #expect(result.unreadable.count == 1 && result.unreadable[0].contains("gate-2"),
            "the skip was not reported: \(result.unreadable)")
        
        let survived = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_source WHERE note_id = 'gate-2'") ?? 0
        }
        
        #expect(survived == 1, "baseline row deleted because the file could not be read")
    }
    
    @Test("integrate finishes and reports what it could not read, rather than stopping or staying silent")
    func integrateCompletesAndReportsUnreadableDeclaration() throws {
        // Given
        let grounding = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: grounding, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote("gate-6", source: "[\"\(grounding.path)\"]")
        let queue = try DB.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: path) }
        
        let checkedBefore = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_checked_at FROM note_source WHERE note_id = 'gate-6'") ?? -1
        }
        
        try Self.note(id: "gate-6", source: "[\(grounding.path)]")
            .write(to: path, atomically: true, encoding: .utf8)
        
        // When
        let output = try Consolidate.integrate()
        
        // Then
        #expect(output.summary.sourcesUnreadable == 1,
            "integrate reported a clean source pass over a note it could not verify")
        
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT source_checked_at FROM note_source WHERE note_id = 'gate-6'")
        }
        
        #expect(row != nil, "integrate deleted the baseline of a note it merely could not read")
        #expect(row?["source_checked_at"] as Int? == checkedBefore,
            "the skipped note was stamped as if it had been verified")
    }
    
    // 2. ops boundaries reject exactly what the file parser rejects
    @Test("a malformed source in an op is refused by dry-run and apply alike")
    func malformedOpsSourceIsRejectedByDryRunAndApply() throws {
        // Given
        _ = try DB.connect()
        
        // When
        for bad in [[123], [NSNull()], [""], [["foo": "bar"]]] as [Any] {
            let op: [String: Any] = [
                "op": "create_note", "id": "gate-ops", "axis": "flow",
                "title": "t", "summary": "s", "tags": ["flow"], "content": "# body",
                "axis_description": "(test)", "source": bad
            ]
            let dryRun = Transaction.dryRun(["ops": [op], "rationale": "test"])
        
        // Then
            #expect(dryRun.status == "rejected", "dry-run accepted malformed source \(bad)")
            
            let result = home.apply([op])
            
            #expect(result.status != "ok", "apply accepted malformed source \(bad)")
        }
    }
    
    @Test("a refused set_frontmatter leaves the existing declaration untouched")
    func malformedSetFrontmatterSourceCannotEraseAnExistingDeclaration() throws {
        // Given
        let grounding = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: grounding, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote("gate-3", source: "[\"\(grounding.path)\"]")
        let queue = try DB.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: path) }
        
        // When
        let result = home.apply([[
            "op": "set_frontmatter", "id": "gate-3",
            "fields": ["source": [123]]
        ]])
        
        // Then
        #expect(result.status != "ok", "malformed set_frontmatter source applied with status=\(result.status)")
        
        let (document, _) = try Frontmatter.parse(try String(contentsOf: path, encoding: .utf8))
        
        #expect(document.source == [grounding.path], "declaration was overwritten — got \(document.source as Any)")
        
        let rows = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_source WHERE note_id = 'gate-3'") ?? 0
        }
        
        #expect(rows == 1, "note_source row deleted by a rejected op")
    }
    
    @Test("an explicit empty list still clears the declaration — refusing malformed input is not refusing all input")
    func explicitEmptyListStillClearsTheDeclaration() throws {
        // Given
        let grounding = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: grounding, atomically: true, encoding: .utf8)
        
        let path = try Self.writeNote("gate-4", source: "[\"\(grounding.path)\"]")
        let queue = try DB.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: path) }
        
        // When
        let result = home.apply([[
            "op": "set_frontmatter", "id": "gate-4",
            "fields": ["source": [String]()]
        ]])
        
        // Then
        #expect(result.status == "ok", "explicit clear was rejected: \(result.error)")
        
        let (document, _) = try Frontmatter.parse(try String(contentsOf: path, encoding: .utf8))
        
        #expect(document.source ?? [] == [], "explicit [] did not clear the declaration")
        
        let rows = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_source WHERE note_id = 'gate-4'") ?? 0
        }
        
        #expect(rows == 0, "cleared declaration left a stale note_source row")
    }
    
    @Test("every well-formed shape still applies")
    func validShapesStillApply() throws {
        // Given
        _ = try DB.connect()
        
        // When
        let result = home.apply([[
            "op": "create_note", "id": "gate-5", "axis": "flow",
            "title": "t", "summary": "s", "tags": ["flow"], "content": "# body",
            "axis_description": "(test)",
            "source": ["/abs/a.swift", ["path": "/abs/b.swift"]] as [Any]
        ]])
        
        // Then
        #expect(result.status == "ok", "valid mixed shapes rejected: \(result.error)")
        
        let path = Paths.notes.appendingPathComponent("flow/gate-5.md")
        let (document, _) = try Frontmatter.parse(try String(contentsOf: path, encoding: .utf8))
        
        #expect(document.source == ["/abs/a.swift", "/abs/b.swift"])
    }
}
