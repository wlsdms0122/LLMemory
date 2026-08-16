//
//  SectionInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import LLMemory

@Suite("SectionInvariant Tests")
struct SectionInvariantTests {
    // MARK: - Property
    private let sectionEdit = SectionEdit()

    // MARK: - Initializer
    // MARK: - Test
    @Test("distinct section paths are no collision")
    func noCollisionsReturnsEmpty() {
        // When
        let body = "## A\nbody\n\n## B\nbody\n"
        
        // Then
        #expect(sectionEdit.findPathCollisions(body).isEmpty)
    }
    
    @Test("two top-level sections with one title collide, and both lines are reported")
    func topLevelDupDetected() {
        // When
        let body = "## A\nfirst\n\n## A\nsecond\n"
        let collisions = sectionEdit.findPathCollisions(body)
        
        // Then
        #expect(collisions.count == 1)
        #expect(collisions[0].path.display() == "## A")
        #expect(collisions[0].lines == [1, 4])
    }
    
    @Test("two siblings under one parent share a path, so they collide")
    func siblingDupUnderSameParentDetected() {
        // When
        let body = "## BKI-303\n\n### Compare\n### Compare\nbody\n"
        let collisions = sectionEdit.findPathCollisions(body)
        
        // Then
        #expect(collisions.count == 1)
        #expect(collisions[0].path.display() == "## BKI-303 > ### Compare")
        #expect(collisions[0].lines == [3, 4])
    }
    
    @Test("the same title under different parents is a different path")
    func sameTitleUnderDifferentParentsIsOK() {
        // When
        let body = "## A\n### Status\nfoo\n\n## B\n### Status\nbar\n"
        
        // Then
        #expect(sectionEdit.findPathCollisions(body).isEmpty)
    }
    
    @Test("every colliding path is reported, not just the first")
    func multipleCollisionsAllReported() {
        // When
        let body = "## A\nx\n## A\ny\n## B\n### C\n### C\nz\n"
        let paths = sectionEdit.findPathCollisions(body).map { collision in collision.path.display() }.sorted()
        
        // Then
        #expect(paths == ["## A", "## B > ### C"])
    }
    
    @Test("a path repeated three times records all three lines")
    func threeOccurrencesAllLinesRecorded() {
        // When
        let body = "## A\n## A\n## A\n"
        let collisions = sectionEdit.findPathCollisions(body)
        
        // Then
        #expect(collisions.count == 1)
        #expect(collisions[0].lines == [1, 2, 3])
    }
    
    @Test("a heading inside a fence is code, not a section")
    func fencedCodeHeadingsIgnored() {
        // When
        let body = "## Real\n```\n## Not real\n## Not real\n```\n"
        
        // Then
        #expect(sectionEdit.findPathCollisions(body).isEmpty)
    }
    
    @Test("a body whose sections are all addressable passes the assertion")
    func assertResolvableCleanBodyPasses() throws {
        try sectionEdit.assertResolvable("## A\nbody\n## B\nbody\n")
    }
    
    @Test("a body with a collision throws, naming the note it came from")
    func assertResolvableCollisionRaises() {
        // When
        let body = "## A\n## A\n"
        
        // Then
        #expect(throws: SectionError.self) {
            try sectionEdit.assertResolvable(body, noteId: "test-note")
        }
    }
    
    @Test("addressing a colliding path throws rather than picking one of them")
    func findSectionAmbiguousError() throws {
        // When
        let body = "## A\nfirst\n## A\nsecond\n"
        let path = try sectionEdit.parsePath("## A")
        
        // Then
        #expect(throws: SectionError.self) {
            _ = try sectionEdit.findSection(body, path: path)
        }
    }
}
