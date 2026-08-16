//
//  SessionIdTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/15/26.
//

import Testing
@testable import LLMemory

@Suite("SessionId Tests")
struct SessionIdTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("an empty string is not a session — it is the same absence as no string at all")
    func emptyIsAbsence() {
        // Activity windows group by this value and an absent one is its own
        // group, so an empty session would have opened a window nobody meant.
        #expect(SessionId("") == nil)
        #expect(SessionId(nil) == nil)
        #expect(SessionId("") == SessionId(nil))
    }

    @Test("anything else is carried through unchanged")
    func nonEmptyIsCarried() {
        #expect(SessionId("task-a")?.rawValue == "task-a")
        #expect(SessionId(" ")?.rawValue == " ", "only emptiness is absence — whitespace is a caller's choice")
    }

    // MARK: - Private
}
