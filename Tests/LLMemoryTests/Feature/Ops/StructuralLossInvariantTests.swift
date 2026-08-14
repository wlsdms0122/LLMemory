//
//  StructuralLossInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Structural ops rewrite what a note is. Every one of them can lose something markdown cannot restate
// — a trashed body, a learned edge, its provenance — so each has to either carry it across or refuse.
@Suite("StructuralLossInvariant Tests", .serialized)
struct StructuralLossInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private let trashLookup = TrashedNoteLookup()

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("trashing an id twice keeps both bodies, and the newest one is what findTrashedFile returns")
    func trashDoesNotClobberExistingTrashEntry() throws {
        // Given
        #expect(home.createNote(id: "trsh-dup", content: "## A\nFIRST_BODY_alpha\n").status == "ok")
        #expect(home.apply(["op": "delete_note", "id": "trsh-dup", "reason": "first"]).status == "ok")
        
        guard let firstTrash = try trashLookup.findTrashedFile("trsh-dup")?.url else {
            throw TestFailure("setup: the first incarnation was not trashed")
        }
        
        #expect(try String(contentsOf: firstTrash, encoding: .utf8).contains("FIRST_BODY_alpha"))
        
        // When — the id is taken again and trashed again.
        #expect(home.createNote(id: "trsh-dup", content: "## A\nSECOND_BODY_beta\n").status == "ok")
        #expect(home.apply(["op": "delete_note", "id": "trsh-dup", "reason": "second"]).status == "ok")
        
        // Then
        let trashDirectory = firstTrash.deletingLastPathComponent()
        let preserved = ((try? FileManager.default.contentsOfDirectory(
            at: trashDirectory,
            includingPropertiesForKeys: nil
        )) ?? []).filter { url in
            url.lastPathComponent.hasPrefix("trsh-dup") && url.pathExtension == "md"
        }
        
        #expect(try String(contentsOf: firstTrash, encoding: .utf8).contains("FIRST_BODY_alpha"),
            "the first trashed incarnation was clobbered by the second — silent loss")
        #expect(preserved.count == 2,
            "expected both incarnations preserved, found \(preserved.map(\.lastPathComponent))")
        
        let latest = try trashLookup.findTrashedFile("trsh-dup")?.url
        
        #expect(latest != nil)
        #expect(try String(contentsOf: latest!, encoding: .utf8).contains("SECOND_BODY_beta"),
            "findTrashedFile should return the most recently trashed incarnation")
    }
    
    @Test("the trash path an op predicts is the path it writes — a rollback can only undo what it knows")
    func trashCollisionWriteMatchesTouchesDestination() throws {
        // Given
        #expect(home.createNote(id: "trsh-snap", content: "## A\nfirst\n").status == "ok")
        #expect(home.apply(["op": "delete_note", "id": "trsh-snap", "reason": "first"]).status == "ok")
        #expect(home.createNote(id: "trsh-snap", content: "## A\nsecond\n").status == "ok")
        
        // When
        let source = try home.read { database in try FetchNotePathTransaction(nid: "trsh-snap").perform(database) }
        
        guard let source, let predicted = Trash.destination(of: source) else {
            throw TestFailure("setup: no trash destination for the live note")
        }
        
        // Then
        #expect(predicted.path != (try Trash.pathFor("cortex/trsh-snap.md")).path,
            "a collision must resolve to a suffixed path, not the occupied base")
        #expect(home.apply(["op": "delete_note", "id": "trsh-snap", "reason": "second"]).status == "ok")
        #expect(FileManager.default.fileExists(atPath: predicted.path),
            "the write landed where touches did not predict — a rollback would orphan it")
        #expect(try String(contentsOf: predicted, encoding: .utf8).contains("second"))
    }
    
    @Test("a split hands the source's links to its children before the source is deleted")
    func splitRedistributesLinksBeforeSourceDelete() throws {
        // Given
        try seedSourceWithNeighborLink()
        
        // When
        #expect(home.apply(["op": "split_note", "from_id": "bbb-src", "into": splitInto()]).status == "ok")
        
        // Then
        let childEdges = try home.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM note_links
                WHERE kind = 'cooccur'
                  AND (src IN ('zzz-child','ddd-child') OR dst IN ('zzz-child','ddd-child'))
                """) ?? 0
        }
        
        #expect(childEdges >= 1,
            "the children inherited none of the source's links — redistribution ran after the delete cascade")
        #expect(try edges(touching: "bbb-src") == 0, "the deleted source still has edges")
    }
    
    @Test("a redistributed undirected edge stays canonical, so it cannot be stored twice")
    func splitRedistributedEdgesStayCanonical() throws {
        // Given
        try seedSourceWithNeighborLink()
        
        // When
        #expect(home.apply(["op": "split_note", "from_id": "bbb-src", "into": splitInto()]).status == "ok")
        
        // Then
        let nonCanonical = try home.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM note_links WHERE kind IN ('cooccur','assoc') AND src > dst
                """) ?? 0
        }
        
        #expect(nonCanonical == 0, "a redistributed undirected edge was left non-canonical (src > dst)")
    }
    
    @Test("a split invents no reference edge between children that no body actually spells")
    func splitDoesNotSynthesizeCrossChildReferenceEdges() throws {
        // Given
        home.createNote(
            id: "bbb-src",
            content: "## A\nthis section mentions bbb-src inline\n## B\nbeta body\n"
        )
        
        // When
        #expect(home.apply(["op": "split_note", "from_id": "bbb-src", "into": splitInto()]).status == "ok")
        
        // Then
        let crossChildReferences = try home.read { database in
            try Int.fetchOne(database, sql: """
                SELECT COUNT(*) FROM note_links
                WHERE kind = 'reference'
                  AND src IN ('zzz-child','ddd-child') AND dst IN ('zzz-child','ddd-child')
                """) ?? 0
        }
        
        #expect(crossChildReferences == 0, "the split synthesized a reference edge no body backs")
        #expect(try edges(touching: "bbb-src") == 0, "an edge still points at the deleted source")
    }
    
    @Test("migrate's predicted destination is where it writes — the id alone decides it")
    func migrateTouchesMatchesWriteDestination() throws {
        // Given
        home.createNote(id: "mig-src", content: "## A\nbody\n")
        
        let operation: [String: Any] = ["op": "migrate_note", "id": "mig-src", "new_id": "mig.dst"]
        let expected = Paths.file(forId: "mig.dst")
        
        // When
        let touched = try home.readScope { scope in
            try MigrateNoteHandler().touches(operation, scope)
        }
        
        // Then
        #expect(touched.contains(expected),
            "touches omits the real write destination, so a snapshot would not back it up")
    }
    
    @Test("a routed learned edge keeps its provenance, or it escapes provenance-scoped purges")
    func splitPreservesAssocProvenance() throws {
        // Given
        home.createNote(id: "bbb-src", content: "## A\nalpha\n## B\nbeta\n")
        home.createNote(id: "ccc-nbr", content: "## X\nneighbor\n")
        
        try home.database().write { database in
            try database.execute(sql: """
                INSERT OR IGNORE INTO note_links
                    (src, dst, kind, weight, created_at, last_activated_at, provenance)
                VALUES ('bbb-src', 'ccc-nbr', 'assoc', 0.4, 1, 1, 'forge:capture:test-model')
                """)
        }
        
        // When
        let result = home.apply([
            "op": "split_note", "from_id": "bbb-src", "into": splitInto(),
            "routing": [["type": "link", "kind": "assoc", "neighbor": "ccc-nbr", "to": ["zzz-child"]]]
        ])
        
        // Then
        let provenances = try home.read { database in
            try String.fetchAll(database, sql: """
                SELECT provenance FROM note_links
                WHERE kind = 'assoc' AND (src IN ('zzz-child','ddd-child') OR dst IN ('zzz-child','ddd-child'))
                """)
        }
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(!provenances.isEmpty, "the routed assoc edge is missing from the children")
        #expect(provenances.allSatisfy { provenance in provenance == "forge:capture:test-model" },
            "the routed assoc edge lost its provenance, so purge_enrichment can no longer reach it")
    }
    
    @Test("a merge whose file removal fails rolls back whole — no row without a file")
    func mergeFileRemovalFailureRollsBackAtomically() throws {
        // Given
        #expect(home.createNote(
            id: "zomb-into", tags: ["persona"], content: "## Body\ntarget body\n"
        ).status == "ok")
        #expect(home.createNote(
            id: "zomb-from", tags: ["tech"], content: "## Body\nsource body merged in\n"
        ).status == "ok")
        
        let fromPath = Paths.file(forId: "zomb-from")
        
        // When — the directory is read-only, so removing the absorbed file must fail.
        try Self.withReadOnlyDirectory(fromPath.deletingLastPathComponent()) {
            let result = home.apply([
                "op": "merge_notes", "into_id": "zomb-into", "from_ids": ["zomb-from"],
                "merged_content": "## Body\nmerged\n", "summary": "summary", "tags": ["persona"]
            ])
            
            #expect(result.status != "ok", "the merge committed although the file removal failed")
        }
        
        // Then
        #expect(try noteCount(id: "zomb-from") == 1, "the row was deleted even though the transaction failed")
        #expect(FileManager.default.fileExists(atPath: fromPath.path), "the file vanished")
    }
    
    @Test("a split whose source removal fails rolls back whole — no row without a file")
    func splitFileRemovalFailureRollsBackAtomically() throws {
        // Given
        #expect(home.createNote(
            id: "zomb-ssrc", tags: ["tech"], content: "## A\nalpha body\n## B\nbeta body\n"
        ).status == "ok")
        
        let sourcePath = Paths.file(forId: "zomb-ssrc")
        
        // When
        try Self.withReadOnlyDirectory(sourcePath.deletingLastPathComponent()) {
            let result = home.apply(["op": "split_note", "from_id": "zomb-ssrc", "into": [
                [
                    "id": "zomb-c1", "title": "C1", "tags": ["persona"],
                    "summary": "summary", "sections": ["## A"]
                ],
                [
                    "id": "zomb-c2", "title": "C2", "tags": ["persona"],
                    "summary": "summary", "sections": ["## B"]
                ]
            ]])
            
            #expect(result.status != "ok", "the split committed although the source removal failed")
        }
        
        // Then
        #expect(try noteCount(id: "zomb-ssrc") == 1, "the row was deleted even though the transaction failed")
        #expect(FileManager.default.fileExists(atPath: sourcePath.path), "the file vanished")
    }
    
    @Test("a merged-away source is trashed, not destroyed — it can still be restored")
    func mergeTrashesSourceRecoverably() throws {
        // Given
        #expect(home.createNote(id: "trsh-into", content: "## Body\ntarget body\n").status == "ok")
        #expect(home.createNote(id: "trsh-from", content: "## Body\nsource body\n").status == "ok")
        
        // When
        #expect(home.apply([
            "op": "merge_notes", "into_id": "trsh-into", "from_ids": ["trsh-from"],
            "merged_content": "## Body\ntarget body\nsource body\n",
            "summary": "summary", "tags": ["flow"]
        ]).status == "ok")
        
        // Then
        #expect(try trashLookup.findTrashedFile("trsh-from")?.url != nil,
            "the merge hard-deleted the source instead of trashing it")
        #expect(home.apply(["op": "restore", "id": "trsh-from"]).status == "ok")
        #expect(try noteCount(id: "trsh-from") == 1, "the trashed merge source was not restorable")
    }
    
    @Test("a split source is trashed, not destroyed")
    func splitTrashesSourceRecoverably() throws {
        // Given
        #expect(home.createNote(id: "trsh-ssrc", content: "## A\nalpha body\n## B\nbeta body\n").status == "ok")
        
        // When
        #expect(home.apply(["op": "split_note", "from_id": "trsh-ssrc", "into": [
            [
                "id": "trsh-sc1", "title": "C1", "tags": ["flow"],
                "summary": "summary", "sections": ["## A"]
            ],
            [
                "id": "trsh-sc2", "title": "C2", "tags": ["flow"],
                "summary": "summary", "sections": ["## B"]
            ]
        ]]).status == "ok")
        
        // Then
        #expect(try trashLookup.findTrashedFile("trsh-ssrc")?.url != nil,
            "the split hard-deleted the source instead of trashing it")
    }
    
    // MARK: - Private
    // The child ids sort before and after the source's on purpose, so an edge that is only canonical
    // by luck shows up as one that is not.
    private func splitInto() -> [[String: Any]] {
        [
            [
                "id": "zzz-child", "title": "Z", "tags": ["flow"],
                "summary": "summary", "sections": ["## A"]
            ],
            [
                "id": "ddd-child", "title": "D", "tags": ["flow"],
                "summary": "summary", "sections": ["## B"]
            ]
        ]
    }
    
    private func seedSourceWithNeighborLink() throws {
        home.createNote(id: "bbb-src", content: "## A\nalpha body\n## B\nbeta body\n")
        home.createNote(id: "ccc-nbr", content: "## X\nneighbor body\n")
        
        try home.database().write { database in
            try database.execute(sql: """
                INSERT OR IGNORE INTO note_links (src, dst, kind, weight, created_at, last_activated_at)
                VALUES ('bbb-src', 'ccc-nbr', 'cooccur', 1.0, 1, 1)
                """)
        }
    }
    
    private func edges(touching noteId: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM note_links WHERE src = ? OR dst = ?",
                arguments: [noteId, noteId]
            ) ?? 0
        }
    }
    
    private func noteCount(id: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM notes WHERE id = ?", arguments: [id]) ?? 0
        }
    }
    
    private static func withReadOnlyDirectory(_ directory: URL, _ body: () throws -> Void) rethrows {
        let fileManager = FileManager.default
        
        try? fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        
        try body()
    }
}
