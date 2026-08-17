//
//  ConsolidateReportTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("ConsolidateReport Tests", .serialized)
struct ConsolidateReportTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("the tag report surfaces the tags carried by a single note")
    func tagReportSurfacesRareTags() throws {
        // Given
        home.createNote(id: "tag-rare", tags: ["flow", "onlyhere"])
        home.createNote(id: "tag-common-1", tags: ["flow", "shared"])
        home.createNote(id: "tag-common-2", tags: ["flow", "shared"])
        
        // When
        let report = try home.read { database in try FetchTagReportOperation().execute(database) }
        
        // Then
        let rare = Set(report.rare.map(\.tag))
        
        #expect(rare.contains("onlyhere"))
        #expect(!rare.contains("shared"), "a tag on two notes is not rare")
        #expect(!rare.contains("flow"))
    }
    
    @Test("compacting with a retention window wider than the data drops nothing")
    func compactOldEventsKeepsEverythingInsideRetention() throws {
        // When
        let result = try home.database().write { database in
            try CompactOldEventsOperation(now: home.now, retentionSec: 99_999_999).execute(database)
        }
        
        // Then
        #expect(result.compacted == 0)
    }
}
