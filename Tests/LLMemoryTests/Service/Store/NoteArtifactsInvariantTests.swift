//
//  NoteArtifactsInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("NoteArtifactsInvariant Tests", .serialized)
struct NoteArtifactsInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private let indexer = Indexer()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    
    @Test("every table that cascades from a note is classified — an unclassified one is invisible to the ops that must carry it")
    func everyNoteCascadeTableIsClassified() throws {
        // When
        let queue = try home.storage.connect()
        let cascade = try queue.read { db in try FetchNoteCascadeTablesOperation().execute(db) }
        
        // Then
        #expect(!cascade.isEmpty)
        
        for table in cascade {
            #expect(NoteArtifactPolicy.tableDisposition[table] != nil,
                """
                    note-cascade table '\(table)' is unclassified — add it to \
                    NoteArtifactPolicy.tableDisposition as reconstructable, preserved or acceptedLoss. \
                    A preserved one needs the snapshot and restore path too.
                    """)
        }
    }
    
    @Test("every artifact declares what a split does with it, so none is silently dropped")
    func everyArtifactHasSplitPolicy() throws {
        // When
        let queue = try home.storage.connect()
        let cascade = Set(try queue.read { db in try FetchNoteCascadeTablesOperation().execute(db) })
        
        // Then
        for table in cascade where table != "note_links" {
            #expect(NoteArtifactPolicy.tableSplitPolicy[table] != nil,
                "cascade table '\(table)' has no SplitPolicy — classify it in NoteArtifactPolicy.tableSplitPolicy")
        }
        
        for (table, _) in NoteArtifactPolicy.tableSplitPolicy {
            #expect(cascade.contains(table), "tableSplitPolicy '\(table)' is not a real cascade table")
            #expect(table != "note_links",
                "note_links is classified by kind (NoteArtifactPolicy.splitPolicy), not as a table")
        }
    }
    
    @Test("every artifact a rebuild is allowed to discard has something that regenerates it")
    func everyRebuildKindHasARegenerator() {
        // Then
        #expect(NoteArtifactPolicy.reconstructableLinkKinds == [LinkKind.reference.rawValue])
    }
    
        @Test("every declared disposition names a table that actually exists")
    func dispositionEntriesAreRealCascadeTables() throws {
        // When
        let queue = try home.storage.connect()
        let cascade = Set(try queue.read { db in try FetchNoteCascadeTablesOperation().execute(db) })
        
        // Then
        for (table, _) in NoteArtifactPolicy.tableDisposition {
            #expect(cascade.contains(table), "tableDisposition names '\(table)', which is not a real cascade table")
        }
    }
    
    @Test("a rebuild preserves every artifact declared as preserved")
    func rebuildPreservesEveryPreservedTable() throws {
        // When
        home.createNote(id: "rt-a", content: "## Body\nzephyrine quasar distinct content\n")
        home.createNote(id: "rt-b", content: "## Body\nbravo distinct content\n")
        
        // Then
        #expect(home.apply([["op": "add_retrieval_terms", "id": "rt-a", "kind": "alias",
            "terms": ["zephyrine quasar"], "provenance": "t"]]).status == "ok")
        #expect(home.apply([["op": "dismiss_candidate", "id": "rt-a", "kind": "split",
            "reason": "keep"]]).status == "ok")
        
        let source = home.url.appendingPathComponent("rt-src.txt")
        
        try "grounding".write(to: source, atomically: true, encoding: .utf8)
        
        #expect(home.apply([["op": "create_note", "id": "rt-c", "title": "t",
            "tags": ["flow"], "summary": "s", "content": "## Body\nc\n",
            "source": [source.path]]]).status == "ok")
        
        try home.write { db in
            try db.execute(sql: "INSERT INTO ripple_flags (note_id, flag, created_at, last_flagged_at) VALUES ('rt-a','reconsolidate',1,1)")
            try db.execute(sql: "INSERT OR IGNORE INTO note_links (src,dst,kind,weight,created_at,last_activated_at) VALUES ('rt-a','rt-b','cooccur',1.0,1,1)")
            try db.execute(sql: "INSERT OR IGNORE INTO note_links (src,dst,kind,weight,created_at,last_activated_at) VALUES ('rt-a','rt-b','assoc',1.0,1,1)")
        }
        
        let preserved = NoteArtifactPolicy.tableDisposition.filter { entry in entry.value == .preserved }.map { entry in entry.key }
        let counts: ([String]) throws -> [String: Int] = { tables in
            try home.read { db in
                var counted: [String: Int] = [:]
                
                for table in tables {
                    counted[table] = try Int.fetchOne(db, sql: "SELECT count(*) FROM \(table)") ?? 0
                }
                
                return counted
            }
        }
        let before = try counts(preserved)
        
        for table in preserved {
            #expect(before[table]! > 0, "the round-trip fixture never fills '\(table)' — a newly preserved table needs data added above")
        }
        
        _ = try indexer.buildLocked(home.database(), home.brain, rebuild: true)
        
        let after = try counts(preserved)
        
        for table in preserved {
            #expect(after[table]! == before[table]!, "the rebuild lost '\(table)': \(before[table]!) → \(after[table]!)")
        }
    }
}
