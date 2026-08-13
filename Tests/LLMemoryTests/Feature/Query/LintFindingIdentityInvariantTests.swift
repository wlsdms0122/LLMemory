//
//  LintFindingIdentityInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// A finding is addressed by its identity, and dismissing one must not silence another. Two findings
// that collapse onto one identity take a real defect down with the one someone reviewed.
@Suite("LintFindingIdentityInvariant Tests", .serialized)
struct LintFindingIdentityInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("no two findings from the document rules share one identity")
    func repeatedSubjectsDoNotCollideAcrossDocumentRules() {
        // When
        let outputs = Self.documentFindings(nid: "identity-1")
        
        // Then
        var seen: [String: String] = [:]
        
        for output in outputs {
            let identity = "\(output.target.storageKey)\u{0}\(output.code)\u{0}\(output.key ?? "<nil>")"
            
            #expect(seen[identity] == nil, """
                two \(output.code) findings share one identity (key \(output.key ?? "<nil>")): \
                '\(seen[identity] ?? "")' and '\(output.message)'
                """)
            
            seen[identity] = output.message
        }
        
        let codes = Set(outputs.map(\.code))
        
        #expect(codes.contains("bare-hash-line"), "the probe body no longer trips bare-hash-line")
        #expect(codes.contains("wikilink-style"), "the probe body no longer trips wikilink-style")
    }
    
    @Test("repeated occurrences fold into one finding that still names the lines it folded")
    func collapsedFindingStillNamesEveryOccurrence() {
        // When
        let outputs = Self.documentFindings(nid: "identity-2")
        
        // Then
        let hashFindings = outputs.filter { output in output.code == "bare-hash-line" }
        let wikiFindings = outputs.filter { output in output.code == "wikilink-style" }
        
        #expect(hashFindings.count == 2, "expected one finding per distinct line text")
        #expect(hashFindings.filter { finding in finding.message.contains("+1 more at line") }.count == 1,
            "the repeated line did not fold, or folded without naming its other occurrence")
        #expect(wikiFindings.count == 2, "expected one finding per distinct id")
        #expect(wikiFindings.filter { finding in finding.message.contains("+1 more at line") }.count == 1,
            "the repeated id did not fold, or folded without naming its other occurrence")
    }
    
    @Test("the same contract holds over a real note, not only over a body handed to the engine")
    func lintOverARealNoteEnforcesTheContract() throws {
        // Given
        let result = home.createNote(
            id: "identity-3",
            content: Self.opsSafeRepeatingBody,
            fields: ["axis_description": "(test)"]
        )
        
        #expect(result.status == "ok", "setup: \(result.error)")
        
        // When
        let issues = try home.readScope { scope in try Lint.lintAll(scope) }
        
        // Then
        #expect(issues.contains { issue in issue.target.subject == "identity-3" },
            "the probe note produced no findings at all")
    }
    
    @Test("two sections with the same title under different parents stay distinct findings")
    func sameTitledSectionsUnderDifferentParentsStayDistinct() {
        // Given
        let body = """
        # Account
        ### Detail

        # Card
        ### Detail

        """
        
        // When
        let outputs = LintEngine.run(
            LintRules.documentRules,
            over: LintRules.document(nid: "identity-4", body: body)
        )
        
        // Then
        for code in ["heading-skip", "adjacent-empty-heading", "empty-section"] {
            let found = outputs.filter { output in output.code == code }
            
            guard !found.isEmpty else { continue }
            
            let keys = found.map { finding in finding.key ?? "<nil>" }
            
            #expect(Set(keys).count == found.count,
                "\(code) merged same-titled sections under different parents: \(keys)")
            #expect(keys.allSatisfy { key in key.contains("Account") || key.contains("Card") },
                "\(code) dropped the parent from its key: \(keys)")
        }
        
        #expect(outputs.filter { output in output.code == "heading-skip" }.count == 2,
            "the probe body no longer produces two heading-skip findings")
    }
    
    @Test("a corpus rule that collides with itself is reported as an error, not run anyway")
    func duplicateCorpusIdentitiesAreReportedNotFatal() throws {
        // When
        let collided = try home.readScope { scope in
            try Lint.lintAll(scope, corpusRules: [CollidingCorpusRule()])
        }
        let clean = try home.readScope { scope in
            try Lint.lintAll(scope, corpusRules: [DistinctCorpusRule()])
        }
        
        // Then
        #expect(collided.contains { issue in
            issue.code == "lint-rule-identity-collision" && issue.severity == "error"
        }, "a colliding corpus rule got past lintAll: \(collided.map(\.code))")
        #expect(!clean.contains { issue in issue.code == "lint-rule-identity-collision" })
    }
    
    @Test("two mistyped fields on one note stay two findings — one review must not close both")
    func aCollidingRuleDoesNotSilenceTheRestOfTheSurface() throws {
        // Given
        home.createNote(id: "blast-note")
        
        let file = try home.indexedPath(of: "blast-note")
        let text = try String(contentsOf: file, encoding: .utf8)
        
        try text.replacingOccurrences(of: "summary:", with: "priorty: x\nsumary: y\nsummary:")
            .write(to: file, atomically: true, encoding: .utf8)
        
        _ = try home.storage.writeLock {
            try home.database().write { database in try ReindexNoteFileTransaction(path: file).perform(database) }
        }
        
        // When
        let issues = try home.readScope { scope in try Lint.lintAll(scope) }
        
        // Then
        #expect(issues.filter { issue in issue.code == "field-typo" }.count == 2,
            "the two mistyped fields collapsed onto one identity")
        #expect(!issues.contains { issue in issue.code == "lint-rule-identity-collision" })
    }
    
    @Test("a note subject and a corpus subject spelled the same are still two subjects")
    func noteAndCorpusSubjectsWithTheSameSpellingDoNotCollide() {
        // Given
        let noteIssue = Lint.Issue("warn", "isolated", "n", .note("alpha"), key: nil)
        let corpusIssue = Lint.Issue("warn", "isolated", "c", .corpus("alpha"), key: nil)
        
        // Then
        #expect(Lint.checked([noteIssue, corpusIssue]).count == 2)
    }
    
    // MARK: - Private
    // Every construct here appears twice on purpose: once to produce a finding, once to give the
    // identity a chance to collide with it.
    private static let repeatingBody = """
    # Background
    #unknown-banking-term channel notes
    the body points at [[some-note]], then points at [[some-note]] again.
    #unknown-banking-term channel notes
    #another-channel looks the same
    and [[other-note]] appears once.

    ## List
    ### Detail

    ## List
    ### Detail

    """
    
    // The same probe, minus the duplicate section path that create_note would refuse.
    private static let opsSafeRepeatingBody = """
    # Background
    #unknown-banking-term channel notes
    the body points at [[some-note]], then points at [[some-note]] again.
    #unknown-banking-term channel notes
    #another-channel looks the same
    and [[other-note]] appears once.

    ## List
    content

    """
    
    private static func documentFindings(nid: String) -> [LintEngine.Output] {
        LintEngine.run(LintRules.documentRules, over: LintRules.document(nid: nid, body: repeatingBody))
    }
}
