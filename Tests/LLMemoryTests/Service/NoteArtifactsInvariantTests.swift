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
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    
    @Test("every table that cascades from a note is classified — an unclassified one is invisible to the ops that must carry it")
    func everyNoteCascadeTableIsClassified() throws {
        // When
        let queue = try home.storage.connect()
        let cascade = try queue.read { db in try NoteArtifacts.noteCascadeTables(db) }
        
        // Then
        #expect(!cascade.isEmpty)
        
        for table in cascade {
            #expect(NoteArtifacts.tableDisposition[table] != nil,
                """
                    note-cascade table '\(table)' is unclassified — add it to \
                    NoteArtifacts.tableDisposition as reconstructable, preserved or acceptedLoss. \
                    A preserved one needs the snapshot and restore paths too.
                    """)
        }
    }
    
    @Test("every artifact declares what a split does with it, so none is silently dropped")
    func everyArtifactHasSplitPolicy() throws {
        // When
        let queue = try home.storage.connect()
        let cascade = Set(try queue.read { db in try NoteArtifacts.noteCascadeTables(db) })
        
        // Then
        for table in cascade where table != "note_links" {
            #expect(NoteArtifacts.tableSplitPolicy[table] != nil,
                "cascade table '\(table)' has no SplitPolicy — classify it in NoteArtifacts.tableSplitPolicy")
        }
        
        for (table, _) in NoteArtifacts.tableSplitPolicy {
            #expect(cascade.contains(table), "tableSplitPolicy '\(table)' is not a real cascade table")
            #expect(table != "note_links", "note_links is classified by kind (linkKindSplitPolicy), not as a table")
        }
        
        #expect(Set(NoteArtifacts.linkKindSplitPolicy.keys) == Links.allKinds,
            "linkKindSplitPolicy must classify exactly Links.allKinds — a new kind needs a split decision")
    }
    
    @Test("every artifact a rebuild is allowed to discard has something that regenerates it")
    func everyRebuildKindHasARegenerator() {
        // Then
        #expect(NoteArtifacts.reconstructableLinkKinds == [Links.kindReference])
    }
    
    @Test("every artifact declares whether it should block a delete")
    func everyKindHasDeleteGuardDecision() {
        // Then
        #expect(Links.deleteBlockingKinds.union(Links.deleteNonBlockingKinds) == Links.allKinds,
            "every Links.allKinds member must be classified blocking or non-blocking for delete_note")
        #expect(Links.deleteBlockingKinds.isDisjoint(with: Links.deleteNonBlockingKinds),
            "a kind cannot be both blocking and non-blocking")
        #expect(NoteArtifacts.reconstructableLinkKinds.isSubset(of: Links.allKinds))
        #expect(NoteArtifacts.reconstructableLinkKinds.contains(Links.kindReference))
    }
    
    @Test("every artifact declares whether it is directional, so an undirected one is not stored twice")
    func allKindsAreDirectionClassified() {
        // Then
        #expect(Links.undirectedKinds.union(Links.directedKinds) == Links.allKinds,
            "every Links.allKinds member must be classified directed or undirected")
        #expect(Links.undirectedKinds.isDisjoint(with: Links.directedKinds),
            "a kind cannot be both directed and undirected")
    }
    
    @Test("every declared disposition names a table that actually exists")
    func dispositionEntriesAreRealCascadeTables() throws {
        // When
        let queue = try home.storage.connect()
        let cascade = Set(try queue.read { db in try NoteArtifacts.noteCascadeTables(db) })
        
        // Then
        for (table, _) in NoteArtifacts.tableDisposition {
            #expect(cascade.contains(table), "tableDisposition names '\(table)', which is not a real cascade table")
        }
    }
    
    // Parked. This invariant reads the source text of NoteArtifacts.swift and uses the
    // `// MARK: rebuild` comment as a section boundary — a check hanging off a comment, which one
    // tidy-up was enough to break. What it looks for is worth keeping (a new column on a reconciled
    // table going unhandled in absorbForMerge), so restore it once it derives that from the schema
    // or the code rather than from the prose around them.
    @Test(.disabled("parses source text — restore after the redesign"))
    func absorbForMergeNamesEveryColumnOfReconciledTables() throws {
        // Given
        let reconciled = ["note_usage", "note_retrieval_terms", "ripple_flags", "candidate_dismissals"]
        let memory = try DatabaseQueue()
        let columnsOf: [String: [String]] = try memory.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: Migration1.schema)
            
            var columns: [String: [String]] = [:]
            
            for table in reconciled {
                let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                
                columns[table] = rows.map { row in row["name"] as String }
            }
            
            return columns
        }
        
        let source = PackageSource().file("Sources/LLMemory/Service/NoteArtifacts.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        
        guard let start = text.range(of: "static func absorbForMerge"),
            let end = text.range(of: "// MARK: rebuild") else {
            Issue.record("absorbForMerge region markers not found")
            
            return
        }
        
        let region = String(text[start.lowerBound..<end.lowerBound])
        
        var missing: [String] = []
        
        // When
        for table in reconciled {
            for column in columnsOf[table] ?? [] where column != "note_id" && !region.contains(column) {
                missing.append("\(table).\(column)")
            }
        }
        
        // Then
        #expect(missing.isEmpty, """
            absorbForMerge does not reference a column of a reconciled table — for a new column, \
            decide what merging it means (sum, max, pick a winner, inherit) and put that in the SQL: \
            \(missing)
            """)
    }
    
    @Test("a rebuild preserves every artifact declared as preserved")
    func rebuildPreservesEveryPreservedTable() throws {
        // When
        home.createNote(id: "rt-a", content: "## Body\nzephyrine quasar distinct content\n")
        home.createNote(id: "rt-b", content: "## Body\nbravo distinct content\n")
        
        // Then
        #expect(home.apply([["op": "add_retrieval_terms", "id": "rt-a", "kind": "alias",
            "terms": ["zephyrine quasar"], "provenance": "t"]]).status == "ok")
        #expect(home.apply([["op": "set_note_meta", "id": "rt-a",
            "namespace": "test", "key": "k", "value": "v"]]).status == "ok")
        #expect(home.apply([["op": "dismiss_candidate", "id": "rt-a", "kind": "split",
            "reason": "keep"]]).status == "ok")
        
        let source = home.url.appendingPathComponent("rt-src.txt")
        
        try "grounding".write(to: source, atomically: true, encoding: .utf8)
        
        #expect(home.apply([["op": "create_note", "id": "rt-c", "axis": "flow", "title": "t",
            "tags": ["flow"], "summary": "s", "content": "## Body\nc\n",
            "source": [source.path]]]).status == "ok")
        
        try home.write { db in
            try db.execute(sql: "INSERT INTO ripple_flags (note_id, flag, created_at, last_flagged_at) VALUES ('rt-a','reconsolidate',1,1)")
            try db.execute(sql: "INSERT OR IGNORE INTO note_links (src,dst,kind,weight,created_at,last_activated_at) VALUES ('rt-a','rt-b','cooccur',1.0,1,1)")
            try db.execute(sql: "INSERT OR IGNORE INTO note_links (src,dst,kind,weight,created_at,last_activated_at) VALUES ('rt-a','rt-b','assoc',1.0,1,1)")
        }
        
        let preserved = NoteArtifacts.tableDisposition.filter { entry in entry.value == .preserved }.map { entry in entry.key }
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
        
        _ = try Indexer.buildLocked(home.database(), rebuild: true)
        
        let after = try counts(preserved)
        
        for table in preserved {
            #expect(after[table]! == before[table]!, "the rebuild lost '\(table)': \(before[table]!) → \(after[table]!)")
        }
    }
}
