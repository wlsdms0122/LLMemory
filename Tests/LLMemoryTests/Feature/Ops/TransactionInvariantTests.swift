//
//  TransactionInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// Two sections that share a path cannot be addressed apart, so an op that would create such a pair is
// refused. The rule applies to what an op produces, not to debt the note already carries.
@Suite("TransactionInvariant Tests", .serialized)
struct TransactionInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("creating a note with two sections on the same path is refused, and the path is named")
    func createWithDuplicateSiblingsRejected() {
        // When
        let result = createNote(id: "tinv-dup", content: "## A\n### X\nfoo\n### X\nbar\n")
        
        // Then
        #expect(result.status == "failed")
        #expect(result.error.contains("section invariant violated"))
        #expect(result.error.contains("## A > ### X"), "the colliding path must be named: \(result.error)")
    }
    
    @Test("the same heading under different parents is a different path, so it is allowed")
    func repeatedHeadingUnderDifferentParentsIsFine() {
        // When
        let result = createNote(id: "tinv-clean", content: "## A\n### X\nfoo\n## B\n### X\nbar\n")
        
        // Then
        #expect(result.status == "ok")
    }
    
    @Test("a patch that would introduce a collision is rejected and the file is left alone")
    func patchIntroducingCollisionRejected() throws {
        // Given
        createNote(id: "tinv-p1", content: "## A\n### X\nbody\n")
        
        // When
        let result = home.apply([
            "op": "patch_section", "id": "tinv-p1",
            "section": "## A", "action": "append",
            "content": "\n### X\ndup section\n"
        ])
        
        // Then
        let body = try String(contentsOf: try home.indexedPath(of: "tinv-p1"), encoding: .utf8)
        
        #expect(result.status == "rejected")
        #expect(result.error.contains("section invariant violated"))
        #expect(body.components(separatedBy: "### X").count - 1 == 1, "the rejected patch still landed")
    }
    
    @Test("a collision the note already carries does not block an op that has nothing to do with it")
    func existingCollisionDoesNotBlockUnrelatedOp() throws {
        // Given
        createNote(id: "tinv-legacy", content: "## A\nbody\n## B\nbody\n")
        
        try home.overwriteBody(of: "tinv-legacy", with: "## A\nbody1\n## A\nbody2\n## B\nbody\n")
        
        // When
        let result = home.apply([
            "op": "patch_section", "id": "tinv-legacy",
            "section": "## B", "action": "append",
            "content": "added line\n"
        ])
        
        // Then
        #expect(result.status == "ok", "existing debt must not block an unrelated op")
    }
    
    // MARK: - Private
    @discardableResult
    private func createNote(id: String, content: String) -> OpsTransaction.Result {
        home.createNote(id: id, axis: "tech", tags: ["tech", "test"], content: content)
    }
}
