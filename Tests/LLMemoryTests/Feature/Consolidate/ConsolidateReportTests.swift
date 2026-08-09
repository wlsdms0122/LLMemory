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
    @Test("the axis report counts the notes filed on each axis and calls out the thin ones")
    func axisReportCountsNotesPerAxis() throws {
        // Given
        home.createNote(id: "axis-flow-1", axis: "flow")
        home.createNote(id: "axis-flow-2", axis: "flow")
        home.createNote(id: "axis-tech-1", axis: "tech", tags: ["tech"])
        
        // When
        let report = try home.read { database in try FetchAxisReportTransaction(low: 1, high: 2).perform(database) }
        
        // Then
        let counts = Dictionary(uniqueKeysWithValues: report.all.map { entry in (entry.axis, entry.count) })
        
        #expect(counts["flow"] == 2)
        #expect(counts["tech"] == 1)
        #expect(report.small.map(\.axis).contains("tech"), "an axis at or under `low` is small")
        #expect(report.large.map(\.axis).contains("flow"), "an axis at or over `high` is large")
        #expect(!report.small.map(\.axis).contains("flow"))
    }
    
    @Test("the tag report surfaces the tags carried by a single note")
    func tagReportSurfacesRareTags() throws {
        // Given
        home.createNote(id: "tag-rare", tags: ["flow", "onlyhere"])
        home.createNote(id: "tag-common-1", tags: ["flow", "shared"])
        home.createNote(id: "tag-common-2", tags: ["flow", "shared"])
        
        // When
        let report = try home.read { database in try FetchTagReportTransaction().perform(database) }
        
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
            try CompactOldEventsTransaction(now: home.now, retentionSec: 99_999_999).perform(database)
        }
        
        // Then
        #expect(result.compacted == 0)
    }
}
