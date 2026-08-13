//
//  RestoreEffectInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// Restore brings an id back into existence. Later ops in the same batch have to see that — both as
// something they can build on, and as something they are not allowed to overwrite.
@Suite("RestoreEffectInvariant Tests", .serialized)
struct RestoreEffectInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a create batched after a restore is refused instead of clobbering the note just brought back")
    func restoreThenCreateInOneBatchIsRejected() throws {
        // Given
        trash(id: "rb-note", body: "## A\noriginal\n")
        
        // When
        let result = home.apply([
            ["op": "restore", "id": "rb-note"],
            [
                "op": "create_note", "id": "rb-note", "title": "title",
                "summary": "summary", "tags": ["flow"], "content": "## A\nclobber\n"
            ]
        ])
        
        // Then
        #expect(result.status != "ok", "a batched create overwrote the note restore had just brought back")
        #expect(try Handlers.findTrashedFile("rb-note") != nil, "the original was lost")
    }
    
    @Test("a patch batched after a restore succeeds — restore's creation is visible to the next op")
    func restoreThenPatchInOneBatchSucceeds() throws {
        // Given
        trash(id: "rp-note", body: "## A\nx\n")
        
        // When
        let result = home.apply([
            ["op": "restore", "id": "rp-note"],
            [
                "op": "patch_section", "id": "rp-note", "section": "## A",
                "action": "append", "content": "appended"
            ]
        ])
        
        // Then
        #expect(result.status == "ok", "restore's own creation was invisible to the next op: \(result.error)")
        #expect(try home.bodyText(of: "rp-note").contains("appended"))
    }
    
    // MARK: - Private
    private func trash(id: String, body: String) {
        home.createNote(id: id, content: body)
        
        #expect(home.apply(["op": "delete_note", "id": id, "reason": "test"]).status == "ok")
    }
}
