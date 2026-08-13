//
//  TransactionTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// dry-run and apply run the same validation over the same staged state. Anything dry-run accepts must
// be something apply can commit, and anything it rejects must name the reason.
@Suite("OperationsEngine Tests", .serialized)
struct TransactionTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("an empty op list is rejected — a transaction with nothing in it is a caller mistake")
    func emptyOpsRejected() {
        // When
        let result = OperationsEngine.apply(home.storage, ["ops": [], "rationale": "x"])
        
        // Then
        #expect(result.status == "rejected")
        #expect(result.error.contains("ops must be non-empty list"))
    }
    
    @Test("an unknown op is rejected and its position in the batch is reported")
    func unknownOpRejectedWithIndex() {
        // When
        let result = home.apply(["op": "no_such_op"])
        
        // Then
        #expect(result.status == "rejected")
        #expect(result.rejectedIndex == 0)
    }
    
    @Test("creating a note writes the file and reports the id it created")
    func createNoteSucceeds() {
        // When
        let result = home.createNote(id: "tx-create-1")
        
        // Then
        #expect(result.status == "ok")
        #expect(result.opResults.count == 1)
        #expect(result.opResults[0].ids == ["tx-create-1"])
        #expect(FileManager.default.fileExists(atPath: noteFile("tx-create-1").path))
    }
    
    @Test("dry-run validates without writing anything to disk")
    func dryRunDoesNotPersist() {
        // When
        let result = OperationsEngine.dryRun(home.storage, ["ops": [createOp(id: "tx-dry-1")], "rationale": "test"])
        
        // Then
        #expect(result.status == "ok")
        #expect(!FileManager.default.fileExists(atPath: noteFile("tx-dry-1").path))
    }
    
    @Test("a section invariant violation rolls the whole transaction back, file included")
    func sectionInvariantViolationRollsBack() {
        // When
        let result = home.createNote(id: "tx-inv-1", content: "## A\nfirst\n## A\nsecond\n")
        
        // Then
        #expect(result.status == "failed")
        #expect(!FileManager.default.fileExists(atPath: noteFile("tx-inv-1").path))
    }
    
    @Test("dry-run rejects a patch to a section that does not exist, and names it")
    func dryRunRejectsMissingSection() {
        // Given
        #expect(home.createNote(id: "tx-drs-1", content: "## A\nbody\n").status == "ok")
        
        // When
        let result = OperationsEngine.dryRun(home.storage, [
            "ops": [patchOp(id: "tx-drs-1", section: "## NOPE")],
            "rationale": "test"
        ])
        
        // Then
        #expect(result.status == "rejected")
        #expect((result.error ?? "").contains("section not found"))
    }
    
    @Test("a later op sees the section an earlier op in the same batch created")
    func stagedSectionIsVisibleToTheNextOp() {
        // Given
        #expect(home.createNote(id: "tx-staged-1", content: "## A\nbody\n").status == "ok")
        
        let staged: [String: Any] = [
            "ops": [
                [
                    "op": "patch_section", "id": "tx-staged-1", "section": "## A",
                    "action": "append", "subtree": true, "content": "## B\nnew\n"
                ],
                patchOp(id: "tx-staged-1", section: "## B", content: "- tail")
            ],
            "rationale": "test"
        ]
        
        // Then
        #expect(OperationsEngine.dryRun(home.storage, staged).status == "ok")
        #expect(OperationsEngine.apply(home.storage, staged).status == "ok")
    }
    
    @Test("a database-only op earlier in the batch does not suppress the section check")
    func dbOnlyOpDoesNotSuppressSectionCheck() {
        // Given
        #expect(home.createNote(id: "tx-dbo-1", content: "## A\nbody\n").status == "ok")
        
        // When
        let result = OperationsEngine.dryRun(home.storage, [
            "ops": [
                [
                    "op": "flag", "id": "tx-dbo-1", "kind": "reconsolidate",
                    "reason": "probe"
                ],
                patchOp(id: "tx-dbo-1", section: "## NOPE")
            ],
            "rationale": "test"
        ])
        
        // Then
        #expect(result.status == "rejected")
        #expect((result.error ?? "").contains("section not found"))
    }
    
    @Test("a bad target later in a same-note chain is caught at dry-run, not at apply")
    func sameNoteChainWithBadSecondTargetRejectedAtDryRun() {
        // Given
        #expect(home.createNote(id: "tx-chn-1", content: "## A\nbody\n").status == "ok")
        
        // When
        let result = OperationsEngine.dryRun(home.storage, [
            "ops": [
                patchOp(id: "tx-chn-1", section: "## A", content: "- fine"),
                patchOp(id: "tx-chn-1", section: "## NOPE")
            ],
            "rationale": "test"
        ])
        
        // Then
        #expect(result.status == "rejected")
        #expect((result.error ?? "").contains("section not found"))
    }
    
    @Test("dry-run simulates a create the next op patches, and still catches a bad target")
    func createThenPatchChainSimulated() {
        // Given
        let create = createOp(id: "tx-cp-1")
        
        // When
        let good = OperationsEngine.dryRun(home.storage, [
            "ops": [create, patchOp(id: "tx-cp-1", section: "## A", content: "- ok")],
            "rationale": "test"
        ])
        let bad = OperationsEngine.dryRun(home.storage, [
            "ops": [create, patchOp(id: "tx-cp-1", section: "## NOPE")],
            "rationale": "test"
        ])
        
        // Then
        #expect(good.status == "ok", "the created note must be visible to the patch that follows it")
        #expect(bad.status == "rejected")
        #expect((bad.error ?? "").contains("section not found"))
    }
    
    @Test("a database-only op is rolled back when a later op in the batch fails")
    func dbOnlyOpRolledBackWhenLaterOpFails() throws {
        // Given
        home.createNote(id: "tx-atom1", axis: "flow", tags: ["flow"])
        
        #expect(try retrievalTermCount(of: "tx-atom1") == 0)
        
        // When
        let result = home.apply([
            [
                "op": "add_retrieval_terms", "id": "tx-atom1",
                "terms": [["kind": "alias", "term": "must not survive the failure below"]],
                "provenance": "test"
            ],
            ["op": "delete_note", "id": "nope-does-not-exist-xyz", "reason": "force a failure"]
        ])
        
        // Then
        #expect(result.status != "ok")
        #expect(try retrievalTermCount(of: "tx-atom1") == 0,
            "add_retrieval_terms wrote outside the transaction that failed")
    }
    
    // MARK: - Private
    private func retrievalTermCount(of noteId: String) throws -> Int {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM note_retrieval_terms WHERE note_id = ?",
                arguments: [noteId]
            ) ?? 0
        }
    }
    
    private func noteFile(_ id: String) -> URL {
        Paths.notes.appendingPathComponent("flow/\(id).md")
    }
    
    private func createOp(id: String) -> [String: Any] {
        [
            "op": "create_note", "id": id, "axis": "flow", "title": "title",
            "summary": "summary", "tags": ["flow"], "content": "## A\nbody\n"
        ]
    }
    
    private func patchOp(id: String, section: String, content: String = "- x") -> [String: Any] {
        ["op": "patch_section", "id": id, "section": section, "action": "append", "content": content]
    }
}
