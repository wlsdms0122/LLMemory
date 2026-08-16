//
//  UnreadableNoteGateInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// A note whose file cannot be parsed is not the same as a note that is not there. Treating the two
// alike lets a guard report "nothing to check" when what it means is "I could not look".
@Suite("UnreadableNoteGateInvariant Tests", .serialized)
struct UnreadableNoteGateInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    private var trashLookup: TrashedNoteLookup { TrashedNoteLookup(layout: home.layout) }

    private let noteFile = NoteFile()

    private var detector: CandidateDetector { CandidateDetector(brain: home.brain) }

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("the two read surfaces differ on absence and agree on corruption")
    func theTwoReadSurfacesDifferOnAbsenceAndAgreeOnCorruption() throws {
        // Given
        let absent = home.url.appendingPathComponent("cortex/nope.md")
        let unreadable = home.url.appendingPathComponent("cortex/here.md")
        
        try FileManager.default.createDirectory(
            at: unreadable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "no frontmatter at all\n".write(to: unreadable, atomically: true, encoding: .utf8)
        
        // Then
        #expect(try noteFile.readNoteIfPresent(at: absent) == nil, "absence is an answer, not an error")
        #expect(throws: (any Error).self) { try noteFile.requireNote(at: absent) }
        #expect(throws: (any Error).self) { try noteFile.readNoteIfPresent(at: unreadable) }
        #expect(throws: (any Error).self) { try noteFile.requireNote(at: unreadable) }
    }
    
    @Test("a template edit is refused when a document it governs cannot be read")
    func templateGateRefusesToPassAnUnreadableDocument() throws {
        // Given
        try seedTemplate(id: "tpl-u", documentId: "doc-u")
        
        _ = try corrupt(id: "doc-u", body: "# A\nonly A now\n")
        
        // When
        let result = home.apply([
            "op": "patch_section", "id": "tpl-u", "section": "# A",
            "action": "append", "content": "extra guidance."
        ])
        
        // Then
        #expect(result.status == "failed", "the template edit committed over a document it could not read")
        #expect(result.error.contains("doc-u"), "unexpected: \(result.error)")
        #expect(result.error.contains("unverifiable"), "unexpected: \(result.error)")
    }
    
    @Test("readable drift is still reported as drift, not as unreadable")
    func templateGateStillDistinguishesPlainDrift() throws {
        // Given
        try seedTemplate(id: "tpl-v", documentId: "doc-v")
        try home.overwriteBody(of: "doc-v", with: "# A\nx\n")
        
        // When
        let result = home.apply([
            "op": "patch_section", "id": "tpl-v", "section": "# A",
            "action": "append", "content": "extra."
        ])
        
        // Then
        #expect(result.status == "failed")
        #expect(result.error.contains("template frame"), "unexpected: \(result.error)")
        #expect(!result.error.contains("unverifiable"), "readable drift must not report as unreadable")
    }
    
    @Test("integrity level 1 reports a note that is present but unreadable, not only a missing one")
    func integrityL1ReportsUnreadableNotOnlyMissing() throws {
        // Given
        home.createNote(id: "il1-ok")
        home.createNote(id: "il1-bad")
        
        _ = try corrupt(id: "il1-bad", body: "garbage, no frontmatter\n")
        
        // When
        let issues = try home.read { database in try CheckCorpusIntegrityL1Transaction().perform(database, home.brain).issues }
        
        // Then
        #expect(issues.contains { issue in issue.contains("il1-bad") && issue.contains("unreadable") },
            "a present-but-unparseable note passed every fileExists guard: \(issues)")
        #expect(!issues.contains { issue in issue.contains("il1-ok") })
    }
    
    @Test("the FTS sweep refills what it can and names what it could not read")
    func ftsReconcileReportsWhatItCouldNotRefill() throws {
        // Given
        home.createNote(id: "fts-ok")
        home.createNote(id: "fts-bad")
        
        _ = try corrupt(id: "fts-bad", body: "garbage\n")
        
        // When
        let output = try home.storage.writeLock {
            try home.database().write { database -> (orphansPruned: Int, refilled: Int, unreadable: [String]) in
                try database.execute(sql: "DELETE FROM notes_fts WHERE id IN ('fts-ok','fts-bad')")
                
                return try PruneFtsOrphansTransaction().perform(database, home.brain)
            }
        }
        
        // Then
        #expect(output.refilled == 1, "one bad note must not stop the sweep")
        #expect(output.unreadable.count == 1 && output.unreadable[0].contains("fts-bad"),
            "the skip was reported as a completed reconcile: \(output)")
    }
    
    @Test("restore tells 'not in trash' apart from 'cannot read what is in trash'")
    func restoreDistinguishesNotInTrashFromCannotRead() throws {
        // Given
        home.createNote(id: "tr-gone")
        
        #expect(home.apply(["op": "delete_note", "id": "tr-gone", "reason": "test"]).status == "ok")
        
        // When
        let missing = home.apply(["op": "restore", "id": "tr-never"])
        
        // Then
        #expect(missing.status != "ok")
        #expect(missing.error.contains("not in trash"), "unexpected: \(missing.error)")
        
        // When — the trashed file is there but unreadable.
        let trashed = try #require(try trashLookup.findTrashedFile("tr-gone")?.url)
        
        try "corrupted\n".write(to: trashed, atomically: true, encoding: .utf8)
        
        let blind = home.apply(["op": "restore", "id": "tr-gone"])
        
        // Then
        #expect(blind.status != "ok")
        #expect(blind.error.contains("cannot resolve"), "unexpected: \(blind.error)")
        #expect(!blind.error.contains("not in trash: tr-gone"),
            "an unreadable trash file was reported as the note not existing")
    }
    
    @Test("one corrupt file in trash does not block restoring anything else")
    func oneCorruptTrashFileDoesNotBlockOtherRestores() throws {
        // Given
        for id in ["tr-a", "tr-b"] {
            home.createNote(id: id)
            
            #expect(home.apply(["op": "delete_note", "id": id, "reason": "test"]).status == "ok")
        }
        
        let corrupted = try #require(try trashLookup.findTrashedFile("tr-a")?.url)
        
        try "corrupted\n".write(to: corrupted, atomically: true, encoding: .utf8)
        
        // When
        let result = home.apply(["op": "restore", "id": "tr-b"])
        
        // Then
        #expect(result.status == "ok",
            "a corrupt neighbour in trash blocked an unrelated restore: \(result.error)")
    }
    
    @Test("the section gate reports a file it cannot read instead of passing it")
    func sectionGateReportsAFileItCannotRead() throws {
        // Given
        home.createNote(id: "sg-note")
        
        let file = try corrupt(id: "sg-note", body: "garbage\n")
        
        // When
        let violation = home.operationsEngine.checkSectionInvariants(home.layout, affected: [file], backups: [(file, nil)])
        
        // Then
        #expect(violation?.contains("sg-note") == true, "unexpected: \(violation ?? "nil")")
        #expect(violation?.contains("unverifiable") == true, "unexpected: \(violation ?? "nil")")
    }
    
    @Test("the section gate still skips a file that is simply not there")
    func sectionGateStillSkipsAnAbsentFile() {
        // Given
        let absent = home.url.appendingPathComponent("cortex/deleted.md")
        
        // Then
        #expect(home.operationsEngine.checkSectionInvariants(home.layout, affected: [absent], backups: [(absent, nil)]) == nil)
    }
    
    @Test("the lifecycle stamp refuses to record a shape it could not measure")
    func stampRefusesToRecordAShapeItCouldNotMeasure() throws {
        // Given
        home.createNote(id: "st-note", content: "## A\nx\n## B\ny\n")
        
        let before = try wordCount(of: "st-note")
        
        #expect((before ?? 0) > 0)
        
        let file = try corrupt(id: "st-note", body: "garbage\n")
        
        // Then — unreadable, then absent: neither may be recorded as a measurement.
        #expect(throws: (any Error).self) { try stampLifecycle(of: "st-note") }
        
        try FileManager.default.removeItem(at: file)
        
        #expect(throws: (any Error).self) { try stampLifecycle(of: "st-note") }
        #expect(try wordCount(of: "st-note") == before,
            "the shape was overwritten with a zero it never measured")
    }
    
    @Test("a single-note query fails on its own unreadable anchor rather than answering blind")
    func aSingleNoteQueryFailsOnItsOwnUnreadableAnchor() throws {
        // Given
        home.createNote(id: "an-note", content: "## A\nx\n")
        
        _ = try corrupt(id: "an-note", body: "garbage\n")
        
        // Then
        #expect(throws: (any Error).self) {
            try home.readScope { scope in try detector.neighbors(scope, noteId: "an-note", k: 3) }
        }
    }
    
    @Test("a corpus sweep survives one unreadable note — it drops that note, not the sweep")
    func corpusSweepsSurviveOneUnreadableNote() throws {
        // Given
        let large = "## A\n" + String(repeating: "word ", count: 500) + "\n## B\n"
            + String(repeating: "text ", count: 500) + "\n## C\nx\n## D\ny\n"
        
        home.createNote(id: "sw-ok", tags: ["flow", "t1", "t2"], content: large)
        home.createNote(id: "sw-bad", tags: ["flow", "t1", "t2"], content: large)
        
        _ = try corrupt(id: "sw-bad", body: "garbage\n")
        
        // When
        try home.readScope { scope in
            let split = try detector.splitCandidates(scope)
            
            // Then
            #expect(split.contains { candidate in candidate.id == "sw-ok" },
                "the readable note fell out of the sweep")
            #expect(!split.contains { candidate in candidate.id == "sw-bad" },
                "an unreadable note was sketched anyway")
            
            _ = try detector.clusters(scope)
            _ = try detector.missingEdges(scope)
            _ = try detector.nearDuplicates(scope)
        }
    }
    
    @Test("restore refuses rather than bring back an older body behind a corrupt newer one")
    func restoreRefusesWhenACorruptFileMayBeTheNewerIncarnation() throws {
        // Given
        home.createNote(id: "tn-x", content: "## A\nfirst\n")
        
        #expect(home.apply(["op": "delete_note", "id": "tn-x", "reason": "test"]).status == "ok")
        
        let first = try #require(try trashLookup.findTrashedFile("tn-x")?.url)
        
        home.createNote(id: "tn-x", content: "## A\nsecond\n")
        
        #expect(home.apply(["op": "delete_note", "id": "tn-x", "reason": "test"]).status == "ok")
        
        let second = try #require(try trashLookup.findTrashedFile("tn-x")?.url)
        
        #expect(second != first, "the two incarnations collapsed onto one file")
        
        try "corrupted\n".write(to: second, atomically: true, encoding: .utf8)
        
        // When
        let result = home.apply(["op": "restore", "id": "tn-x"])
        
        // Then
        #expect(result.status != "ok", "restore brought back an older version behind a corrupt newer one")
        #expect(result.error.contains("older version"), "unexpected: \(result.error)")
    }
    
    // MARK: - Private
    @discardableResult
    private func corrupt(id: String, body: String = "# A\nx\n") throws -> URL {
        let file = try home.indexedPath(of: id)
        
        try body.write(to: file, atomically: true, encoding: .utf8)
        
        return file
    }
    
    private func seedTemplate(id templateId: String, documentId: String) throws {
        #expect(home.apply([
            "op": "create_note", "id": templateId, "title": "template",
            "summary": "summary", "tags": ["template"],
            "content": "# A\nguidance A.\n# B\nguidance B."
        ]).status == "ok")
        #expect(home.apply([
            "op": "create_note", "id": documentId, "title": "document",
            "summary": "summary", "tags": ["flow"], "template": templateId,
            "content": "# A\nx\n# B\ny\n"
        ]).status == "ok")
    }
    
    private func stampLifecycle(of noteId: String) throws {
        try home.storage.writeLock {
            try home.database().write { database in
                try StampNoteLifecycleTransaction(nid: noteId, now: 1, isNew: false).perform(database, home.brain)
            }
        }
    }
    
    private func wordCount(of noteId: String) throws -> Int? {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT word_count FROM notes WHERE id = ?",
                arguments: [noteId]
            )
        }
    }
}
