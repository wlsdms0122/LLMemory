//
//  CheckLevelsTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("CheckLevels Tests", .serialized)
struct CheckLevelsTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("every message a level emits is tagged with the level that produced it")
    func messagesCarryTheirLevelPrefix() throws {
        // When
        let (_, messages) = try Indexer.check(home.database(), level: .l1)
        
        // Then
        for message in messages {
            #expect(message.hasPrefix("L1\t"), "message must start with L1\\t: \(message)")
        }
    }
    
    @Test("a level reports only its own findings — a note on disk but not in the index passes L0, fails L1")
    func levelZeroStopsBeforeTheIndexCheck() throws {
        // Given — the file is well-formed, so only the deeper level can notice it is unindexed.
        try writeUnindexedNote(id: "l0-orphan")
        
        // When
        let (passedLevel0, messagesAtLevel0) = try Indexer.check(home.database(), level: .l0)
        let (passedLevel1, messagesAtLevel1) = try Indexer.check(home.database(), level: .l1)
        
        // Then
        #expect(passedLevel0, "the file's shape is intact, so L0 must pass — got \(messagesAtLevel0)")
        #expect(messagesAtLevel0.isEmpty, "level 0 must not emit a deeper level's findings — got \(messagesAtLevel0)")
        #expect(!passedLevel1)
        #expect(messagesAtLevel1.contains { message in message.hasPrefix("L1\t") },
            "the same state at level 1 must name the missing index row")
    }
    
    @Test("each level carries every finding of the level below it", arguments: [
        (Indexer.IntegrityLevel.l2, Indexer.IntegrityLevel.l1, ["L1"]),
        (Indexer.IntegrityLevel.l3, Indexer.IntegrityLevel.l2, ["L1", "L2"]),
        (Indexer.IntegrityLevel.l4, Indexer.IntegrityLevel.l3, ["L1", "L2", "L3"])
    ])
    func aLevelCarriesTheOneBelowIt(level: Indexer.IntegrityLevel, below: Indexer.IntegrityLevel, prefixes: [String]) throws {
        // When
        let (_, deeper) = try Indexer.check(home.database(), level: level)
        let (_, shallower) = try Indexer.check(home.database(), level: below)
        
        // Then
        let carried = deeper.filter { message in
            prefixes.contains { prefix in message.hasPrefix("\(prefix)\t") }
        }
        
        #expect(carried.count == shallower.count)
    }
    
    @Test("a message is tab-separated and opens with a level tag the reader can dispatch on")
    func messagesHaveTabStructure() throws {
        // Given
        let levelPrefix = try NSRegularExpression(pattern: #"^L[1-4]$"#)
        
        // When
        let (_, messages) = try Indexer.check(home.database(), level: .l4)
        
        // Then
        for message in messages {
            let parts = message.components(separatedBy: "\t")
            
            #expect(parts.count >= 2, "malformed: \(message)")
            
            let head = parts[0] as NSString
            let match = levelPrefix.firstMatch(in: parts[0], range: NSRange(location: 0, length: head.length))
            
            #expect(match != nil, "bad level prefix: \(message)")
        }
    }
    
    // MARK: - Private
    // Written straight to disk so the note exists as a file without ever reaching the index.
    private func writeUnindexedNote(id: String) throws {
        let directory = Paths.notes.appendingPathComponent("flow")
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        id: \(id)
        title: title
        axis: flow
        priority: lazy
        tags: [flow]
        summary: summary
        ---

        # body
        """.write(to: directory.appendingPathComponent("\(id).md"), atomically: true, encoding: .utf8)
    }
}
