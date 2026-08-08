//
//  SectionRowsRobustnessTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Foundation
import Testing
import GRDB
@testable import LLMemory
@Suite("SectionRowsRobustness Tests", .serialized)
struct SectionRowsRobustnessTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a CRLF body decomposes the same way a LF one does")
    func crlfBodySplitsIntoSections() {
        // When
        let body = "intro\r\n## A\r\na-body\r\n## B\r\nb-body\r\n"
        let (preamble, rows) = SectionEdit.sectionRows(body)
        
        // Then
        #expect(preamble == "intro")
        #expect(rows.map { row in row.path } == ["## A", "## B"])
        #expect(rows[0].text.contains("a-body"))
    }
    
    @Test("a note whose head row is missing from the index is reported at level 2")
    func verifyL2DetectsHeadlessFts() throws {
        // Given
        #expect(home.createNote(id: "hl-note", axis: "tech", tags: ["tech"], content: "## A\nbody\n")
            .status == "ok")
        
        let queue = try GRDBStorage.session.connect()
        
        try queue.write { db in
            try db.execute(sql: "DELETE FROM notes_fts WHERE id = 'hl-note' AND section = ''")
        }
        
        let (ok, messages) = try Index.check(level: .l2)
        
        #expect(!ok)
        #expect(messages.contains { message in message.contains("fts-headless") && message.contains("hl-note") })
    }
}
