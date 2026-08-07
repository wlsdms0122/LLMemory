//
//  RestoreCollisionInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("RestoreCollisionInvariant Tests", .serialized)
struct RestoreCollisionInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("restore refuses when the id has been taken again, and leaves the live note intact")
    func restoreRefusesWhenTheIdIsLiveAgain() throws {
        // Given
        home.createNote(id: "rc-note", content: "## A\nold content\n")
        
        #expect(home.apply(["op": "delete_note", "id": "rc-note", "reason": "test"]).status == "ok")
        
        home.createNote(id: "rc-note", content: "## A\nnew content\n")
        
        // When
        let result = home.apply(["op": "restore", "id": "rc-note"])
        
        // Then
        #expect(result.status != "ok", "restore overwrote a live note and committed")
        #expect(result.error.contains("id collision"), "unexpected reason: \(result.error)")
        #expect(try home.bodyText(of: "rc-note").contains("new content"),
            "the live note's body was destroyed")
    }
}
