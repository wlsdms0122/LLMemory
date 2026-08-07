//
//  BudgetGetTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import GRDB
@testable import LLMemory
@Suite("BudgetGet Tests", .serialized)
struct BudgetGetTests {
    // MARK: - Property
    private let home: MemoryHome
    private let body = """
        preamble words here
        ## A
        one two three four five
        ### A1
        six seven
        ## B
        eight nine ten
        ## C
        eleven twelve
        """
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a budget cut lands on a section boundary and keeps a prefix, never a half sentence")
    func budgetCutsAtTopLevelBoundaryPrefixOnly() throws {
        // Then
        #expect(home.createNote(id: "bd", axis: "tech", title: "bd", tags: ["tech"],
            content: body).status == "ok")
        
        let (_, cut) = try QueryFeature.getBudget(home: home.path, id: "bd", budget: 15)
        
        #expect(cut.truncated)
        #expect(cut.shownSections.map { section in section.path } == ["## A"])
        #expect(cut.omitted.map { section in section.path } == ["## B", "## C"])
        #expect(cut.shown.contains("six seven"))
        #expect(!cut.shown.contains("eight"))
        #expect(!cut.shown.contains("eleven"))
        #expect(cut.shownWords < cut.totalWords)
    }
    
    @Test("the budget is a hard cap — even the head and the first unit are subject to it")
    func budgetIsAHardCapEvenForHeadAndFirstUnit() throws {
        // Then
        #expect(home.createNote(id: "bd2", axis: "tech", title: "bd2", tags: ["tech"],
            content: body).status == "ok")
        
        let (_, cut) = try QueryFeature.getBudget(home: home.path, id: "bd2", budget: 1)
        
        #expect(cut.truncated)
        #expect(cut.truncatedWithin == "(preamble)")
        #expect(cut.shownSections.isEmpty)
        #expect(cut.omitted.map { section in section.path } == ["## A", "## B", "## C"])
        #expect(cut.shownWords <= 3)
        #expect(!cut.shown.contains("one two"))
    }
    
    @Test("a first unit too large to fit is cut by line, and the cut is named rather than hidden")
    func budgetHugeFirstUnitAfterEmptyHeadIsLineCutAndNamed() throws {
        // When
        let big = "## A\n" + Array(repeating: "w1 w2 w3 w4 w5", count: 20).joined(separator: "\n")
            + "\n## B\ntail words\n"
        
        // Then
        #expect(home.createNote(id: "bd6", axis: "tech", title: "bd6", tags: ["tech"],
            content: big).status == "ok")
        
        let (_, cut) = try QueryFeature.getBudget(home: home.path, id: "bd6", budget: 10)
        
        #expect(cut.truncated)
        #expect(cut.truncatedWithin == "## A")
        #expect(cut.omitted.map { section in section.path } == ["## B"])
        #expect(cut.shownWords <= 11)
        #expect(cut.shown.hasPrefix("## A"))
    }
    
    @Test("a budget wider than the note returns it whole, with nothing marked as omitted")
    func budgetLargeEnoughIsNotTruncated() throws {
        // Then
        #expect(home.createNote(id: "bd3", axis: "tech", title: "bd3", tags: ["tech"],
            content: body).status == "ok")
        
        let (note, cut) = try QueryFeature.getBudget(home: home.path, id: "bd3", budget: 10_000)
        
        #expect(!cut.truncated)
        #expect(cut.omitted.isEmpty)
        #expect(cut.shown == note.body)
        #expect(cut.shownWords == cut.totalWords)
    }
    
    @Test("a note wrapped in one heading is cut by its children, not shipped as one unit")
    func singletonWrapperDescendsToChildrenAsCutUnits() throws {
        // When
        let wrapped = """
            intro word
            # Report history
            wrapper direct content
            ## 2026-07-01
            one two three four five six
            ## 2026-07-02
            seven eight nine ten
            ## 2026-07-03
            eleven twelve
            """
        
        // Then
        #expect(home.createNote(id: "bd5", axis: "tech", title: "bd5", tags: ["tech"],
            content: wrapped).status == "ok")
        
        let (_, cut) = try QueryFeature.getBudget(home: home.path, id: "bd5", budget: 16)
        
        #expect(cut.truncated)
        #expect(cut.shownSections.map { section in section.path } == ["# Report history > ## 2026-07-01"])
        #expect(cut.omitted.map { section in section.path } ==
            ["# Report history > ## 2026-07-02", "# Report history > ## 2026-07-03"])
        #expect(cut.shown.contains("wrapper direct content"))
        #expect(cut.shown.contains("six"))
        #expect(!cut.shown.contains("seven"))
        
        let (_, slices) = try QueryFeature.getSections(
            home: home.path, id: "bd5", sections: [cut.omitted[0].path])
        
        #expect(slices[0].text.contains("seven eight"))
    }
    
    @Test("content directly under a wrapper is line-cut rather than shipped past the budget")
    func hugeWrapperDirectContentIsLineCutNotShippedWhole() throws {
        // When
        let ledger = Array(repeating: "- entry with several words in it", count: 30)
            .joined(separator: "\n")
        let wrapped = "# Report history\n" + ledger + "\n## 2026-07-01\ntail one\n## 2026-07-02\ntail two\n"
        
        // Then
        #expect(home.createNote(id: "bd7", axis: "tech", title: "bd7", tags: ["tech"],
            content: wrapped).status == "ok")
        
        let (_, cut) = try QueryFeature.getBudget(home: home.path, id: "bd7", budget: 30)
        
        #expect(cut.truncated)
        #expect(cut.truncatedWithin == "# Report history")
        #expect(cut.shownWords <= 30)
        #expect(cut.omitted.map { section in section.path } ==
            ["# Report history > ## 2026-07-01", "# Report history > ## 2026-07-02"])
        #expect(!cut.shown.contains("tail one"))
    }
    
    @Test("a body with no headings has no boundary to cut on, so it is cut by line")
    func headingFreeBodyIsLineCutUnderBudget() throws {
        // Then
        #expect(home.createNote(id: "bd4", axis: "tech", title: "bd4", tags: ["tech"],
            content: "three words here\nand five more words now\n").status == "ok")
        
        let (_, cut) = try QueryFeature.getBudget(home: home.path, id: "bd4", budget: 3)
        
        #expect(cut.truncated)
        #expect(cut.truncatedWithin == "(preamble)")
        #expect(cut.shown == "three words here")
        
        let (note, full) = try QueryFeature.getBudget(home: home.path, id: "bd4", budget: 100)
        
        #expect(!full.truncated)
        #expect(full.shown == note.body)
    }
}
