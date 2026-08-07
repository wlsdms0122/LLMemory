//
//  SectionRowsTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import GRDB
@testable import LLMemory
@Suite("SectionRows Tests")
struct SectionRowsTests {
    // MARK: - Property
    // MARK: - Initializer
    // MARK: - Test
    @Test("text before the first heading is preamble, and each section owns only its own lines")
    func preambleAndDirectContentSplit() {
        // Given
        let body = """
        intro line

        ## A
        a-body
        ### A1
        a1-body
        ## B
        b-body
        """
        let (preamble, rows) = SectionEdit.sectionRows(body)
        
        // Then
        #expect(preamble == "intro line\n")
        #expect(rows.map { row in row.path } == ["## A", "## A > ### A1", "## B"])
        #expect(rows[0].text.contains("a-body"))
        #expect(!rows[0].text.contains("a1-body"))
        #expect(rows[1].text.contains("a1-body"))
        #expect(rows[2].text.contains("b-body"))
    }
    
    @Test("every line lands in exactly one row — the decomposition loses nothing")
    func everyLineLandsInExactlyOneRow() {
        // When
        let body = "pre\n## A\nx\n### B\ny\n#### C\nz\n## D\nw\n"
        let (preamble, rows) = SectionEdit.sectionRows(body)
        let reassembled = ([preamble] + rows.map { row in row.text })
            .filter { text in !text.isEmpty }
            .joined(separator: "\n") + "\n"
        
        // Then
        #expect(reassembled == body)
    }
    
    @Test("a body with no heading is all preamble and no rows")
    func headingFreeBodyIsAllPreamble() {
        // When
        let (preamble, rows) = SectionEdit.sectionRows("just text\nno headings\n")
        
        // Then
        #expect(preamble == "just text\nno headings")
        #expect(rows.isEmpty)
    }
    
    @Test("a heading inside a fence stays inside the section that owns the fence")
    func fencedHeadingsStayInOwnerSection() {
        // When
        let body = "## A\n```\n## not-a-heading\n```\n## B\nb\n"
        let (_, rows) = SectionEdit.sectionRows(body)
        
        // Then
        #expect(rows.map { row in row.path } == ["## A", "## B"])
        #expect(rows[0].text.contains("## not-a-heading"))
    }
}
