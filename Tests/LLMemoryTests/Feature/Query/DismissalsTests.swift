//
//  DismissalsTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Reviewing a candidate and deciding to leave it alone has to be recordable, or the same finding is
// re-judged every cycle. A dismissal is habituation: it goes quiet until the thing itself changes.
@Suite("Dismissals Tests", .serialized)
struct DismissalsTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("dismissing a candidate takes it off the surface")
    func dismissRemovesFromCandidates() throws {
        // Given
        #expect(createSplitCandidate("big-1").status == "ok")
        #expect(try splitCandidateIds().contains("big-1"))
        
        // When
        let result = home.apply([
            "op": "dismiss_candidate", "id": "big-1", "kind": "split", "reason": "one topic"
        ])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(!(try splitCandidateIds().contains("big-1")))
    }
    
    @Test("a dismissed note resurfaces once it grows past the habituation threshold")
    func growthPastThresholdResurfaces() throws {
        // Given — 400 words dismissed, so the threshold is 1.5x of that.
        #expect(createSplitCandidate("big-2", sections: 4, wordsPerSection: 100).status == "ok")
        #expect(dismiss("big-2").status == "ok")
        #expect(!(try splitCandidateIds().contains("big-2")))
        
        // When — 480 words: grown, but not enough.
        #expect(append(to: "big-2", section: "## Section 1", words: 80).status == "ok")
        
        // Then
        #expect(!(try splitCandidateIds().contains("big-2")), "1.2x growth is under the 1.5x threshold")
        
        // When — 680 words.
        #expect(append(to: "big-2", section: "## Section 2", words: 200).status == "ok")
        
        // Then
        #expect(try splitCandidateIds().contains("big-2"), "1.7x growth is over the 1.5x threshold")
    }
    
    @Test("the threshold ratchets with each dismissal — the second one is harder to reopen than the first")
    func thresholdAccumulatesAcrossDismissals() throws {
        // Given
        #expect(createSplitCandidate("big-3", sections: 4, wordsPerSection: 100).status == "ok")
        #expect(dismiss("big-3").status == "ok")
        #expect(append(to: "big-3", section: "## Section 1", words: 400).status == "ok")
        #expect(try splitCandidateIds().contains("big-3"))
        
        // When
        #expect(dismiss("big-3").status == "ok")
        
        // Then
        #expect(try dismissCount(noteId: "big-3", kind: "split") == 2)
        
        // When — grown 1.5x again, which no longer clears the accumulated bar.
        #expect(append(to: "big-3", section: "## Section 2", words: 400).status == "ok")
        
        // Then
        #expect(!(try splitCandidateIds().contains("big-3")), "1.5x growth is under the accumulated 1.75x bar")
    }
    
    @Test("a rebuild survives the dismissal but reopens it — the corpus itself was reorganised")
    func rebuildBumpsGenerationAndReopens() throws {
        // Given
        #expect(createSplitCandidate("big-4").status == "ok")
        #expect(dismiss("big-4").status == "ok")
        #expect(!(try splitCandidateIds().contains("big-4")))
        
        // When
        _ = try Indexer.buildLocked(home.database(), rebuild: true)
        
        // Then
        let survived = try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM candidate_dismissals WHERE note_id='big-4'"
            ) ?? 0
        }
        
        #expect(survived == 1, "a dismissal must survive a rebuild")
        #expect(try splitCandidateIds().contains("big-4"), "the generation bump must reopen it")
    }
    
    @Test("a dismissal silences one candidate surface and nothing else — search is untouched")
    func dismissalIsStimulusSpecific() throws {
        // Given
        #expect(home.apply([
            "op": "create_note", "id": "big-5", "axis": "tech",
            "title": "uniqtoken big note", "summary": "summary", "tags": ["tech", "alpha", "beta"],
            "content": Self.largeBody(sections: 4, wordsPerSection: 120) + "## extra\nzephyrquark marker\n",
            "axis_description": "(test)"
        ]).status == "ok")
        
        // When
        #expect(dismiss("big-5").status == "ok")
        
        // Then
        let hits = try home.read { database in try SearchNotesFTSTransaction(query: "zephyrquark").perform(database) }
        
        #expect(!(try splitCandidateIds().contains("big-5")))
        #expect(hits.contains { hit in hit.id == "big-5" }, "a dismissal must not affect search")
    }
    
    @Test("a dismissal is a judgement, not an artifact — it is never a split route target")
    func dismissalIsNotASplitRouteTarget() throws {
        // Given
        #expect(createSplitCandidate("big-6").status == "ok")
        #expect(dismiss("big-6").status == "ok")
        
        // When
        let targets = try home.read { database in
            try FetchSplitRouteTargetsTransaction(noteId: "big-6").perform(database)
        }
        
        // Then
        #expect(targets.isEmpty, "a dismissal must not surface as a split route target")
    }
    
    @Test("only kinds that are actually dismissible are accepted")
    func dismissibleKindsValidated() throws {
        // Given
        #expect(createSplitCandidate("big-7", sections: 20, wordsPerSection: 150).status == "ok")
        
        // Then
        #expect(dismiss("big-7", kind: "split").status == "ok")
        #expect(dismiss("big-7", kind: "lint:note-oversized").status == "ok")
        #expect(dismiss("big-7", kind: "lint:summary-long").status != "ok")
        #expect(dismiss("big-7", kind: "clusters").status != "ok")
        #expect(dismiss("big-7", kind: "archive").status != "ok")
        #expect(dismiss("big-7", kind: "lint:axis-mismatch").status != "ok")
    }
    
    @Test("a corpus finding carries a corpus target rather than an empty note id")
    func corpusFindingIsTyped() throws {
        // Given
        try seedNearDuplicateTagPair()
        
        // When
        let found = try lintIssues(code: "tag-near-duplicate")
        
        // Then
        #expect(found.count == 1, "expected exactly one pair: \(found.map(\.message))")
        #expect(found.first?.target == .corpus("tag-pair:transfer|transfor"))
    }
    
    @Test("a corpus warn is dismissible, and only through `target`")
    func corpusDismissalRoundTrip() throws {
        // Given
        try seedNearDuplicateTagPair()
        
        #expect(try lintIssues(code: "tag-near-duplicate").count == 1)
        
        // When — addressed as a note, which it is not.
        let wrong = home.apply([
            "op": "dismiss_candidate", "id": "tag-a", "kind": "lint:tag-near-duplicate"
        ])
        
        // Then
        #expect(wrong.status != "ok")
        #expect(wrong.error.contains("corpus:tag-pair:transfer|transfor"),
            "the refusal must hand over the next hop: \(wrong.error)")
        
        // When — addressed as the corpus fact it is.
        let accepted = home.apply([
            "op": "dismiss_candidate", "target": "tag-pair:transfer|transfor",
            "kind": "lint:tag-near-duplicate", "reason": "both are real terms"
        ])
        
        // Then
        #expect(accepted.status == "ok", "\(accepted.error)")
        #expect(try lintIssues(code: "tag-near-duplicate").isEmpty, "the finding must go quiet")
        #expect(try lintIssues(code: "tag-near-duplicate", includeDismissed: true).count == 1,
            "--include-dismissed must still show it")
    }
    
    @Test("a corpus dismissal reopens on reorganisation only — usage counts are not evidence")
    func corpusGateReopensOnGenerationOnly() throws {
        // Given
        try seedNearDuplicateTagPair()
        
        #expect(home.apply([
            "op": "dismiss_candidate", "target": "tag-pair:transfer|transfor",
            "kind": "lint:tag-near-duplicate"
        ]).status == "ok")
        #expect(try lintIssues(code: "tag-near-duplicate").isEmpty)
        
        // When — the tags get used more, which says nothing about whether they are duplicates.
        createTagged("tag-c", tags: ["transfer"])
        createTagged("tag-d", tags: ["transfor"])
        
        // Then
        #expect(try lintIssues(code: "tag-near-duplicate").isEmpty,
            "a change in tag usage is not evidence about a corpus judgement")
        
        // When
        try home.database().write { database in try BumpCandidateGenerationTransaction().perform(database) }
        
        // Then
        #expect(try lintIssues(code: "tag-near-duplicate").count == 1, "a reorganisation must reopen it")
    }
    
    @Test("a corpus dismissal is keyed by the pair, not by which tag is currently more common")
    func corpusKeyIsCountIndependent() throws {
        // Given
        try seedNearDuplicateTagPair()
        
        #expect(home.apply([
            "op": "dismiss_candidate", "target": "tag-pair:transfer|transfor",
            "kind": "lint:tag-near-duplicate"
        ]).status == "ok")
        
        // When — the counts flip, which would reorder a count-derived key.
        createTagged("tag-c", tags: ["transfor"])
        createTagged("tag-d", tags: ["transfor"])
        
        // Then
        let rows = try home.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM corpus_dismissals") ?? 0
        }
        
        #expect(try lintIssues(code: "tag-near-duplicate").isEmpty,
            "the same dismissal must hold when the count order changes")
        #expect(rows == 1, "a new key would create a second row and reset the ratchet")
    }
    
    @Test("a dismissal must be addressed exactly once, with the field its scope calls for")
    func targetAddressingGuards() throws {
        // Given
        try seedNearDuplicateTagPair()
        
        #expect(createSplitCandidate("big-addr").status == "ok")
        
        // When
        let neither = home.apply(["op": "dismiss_candidate", "kind": "lint:tag-near-duplicate"])
        let both = home.apply([
            "op": "dismiss_candidate", "id": "tag-a",
            "target": "tag-pair:transfer|transfor", "kind": "lint:tag-near-duplicate"
        ])
        let wrongScope = home.apply([
            "op": "dismiss_candidate", "target": "tag-pair:transfer|transfor", "kind": "split"
        ])
        
        // Then
        #expect(neither.status != "ok")
        #expect(both.status != "ok")
        #expect(both.error.contains("not both"), "\(both.error)")
        #expect(wrongScope.status != "ok")
        #expect(wrongScope.error.contains("corpus-scope lint warns only"), "\(wrongScope.error)")
    }
    
    @Test("an untargeted corpus finding is a rule defect, reported as an error nobody can dismiss")
    func untargetedCorpusFindingFailsLoud() {
        // When
        let untargeted = Lint.corpusIssue(
            code: "some-corpus-rule",
            severity: "warn",
            .init("two things collide")
        )
        let targeted = Lint.corpusIssue(
            code: "some-corpus-rule",
            severity: "warn",
            .init("m", target: .corpus("k"))
        )
        
        // Then
        #expect(untargeted.severity == "error", "an error cannot be dismissed, so it cannot be swept up")
        #expect(untargeted.code == "lint-rule-untargeted")
        #expect(untargeted.target == .corpus("rule:some-corpus-rule"))
        #expect(untargeted.message.contains("two things collide"), "the original finding must not be lost")
        #expect(!LintRules.dismissibleCodes.contains("lint-rule-untargeted"))
        #expect(targeted.severity == "warn")
        #expect(targeted.target == .corpus("k"))
    }
    
    @Test("no registered corpus rule emits an untargeted finding")
    func registeredCorpusRulesAreTargeted() throws {
        // Given
        try seedNearDuplicateTagPair()
        
        #expect(createSplitCandidate("big-reg").status == "ok")
        
        // When
        let untargeted = try home.readScope { scope in
            try Lint.lintAll(scope).filter { issue in issue.code == "lint-rule-untargeted" }
        }
        
        // Then
        #expect(untargeted.isEmpty, "\(untargeted.map(\.message))")
    }
    
    // MARK: - Private
    private static func largeBody(sections: Int, wordsPerSection: Int) -> String {
        (1 ... sections).map { index in
            "## Section \(index)\n"
                + Array(repeating: "word", count: wordsPerSection).joined(separator: " ")
                + "\n"
        }.joined()
    }
    
    @discardableResult
    private func createSplitCandidate(
        _ id: String,
        sections: Int = 4,
        wordsPerSection: Int = 120
    ) -> OperationsEngine.Result {
        home.createNote(
            id: id,
            axis: "tech",
            title: "big note",
            tags: ["tech", "alpha", "beta"],
            content: Self.largeBody(sections: sections, wordsPerSection: wordsPerSection),
            fields: ["axis_description": "(test)"]
        )
    }
    
    @discardableResult
    private func createTagged(_ id: String, tags: [String]) -> OperationsEngine.Result {
        home.createNote(
            id: id,
            axis: "tech",
            tags: ["tech"] + tags,
            content: "## A\nbody text here\n",
            fields: ["axis_description": "(test)"]
        )
    }
    
    private func seedNearDuplicateTagPair() throws {
        createTagged("tag-a", tags: ["transfer"])
        createTagged("tag-b", tags: ["transfor"])
    }
    
    @discardableResult
    private func dismiss(_ id: String, kind: String = "split") -> OperationsEngine.Result {
        home.apply(["op": "dismiss_candidate", "id": id, "kind": kind])
    }
    
    @discardableResult
    private func append(to id: String, section: String, words: Int) -> OperationsEngine.Result {
        home.apply([
            "op": "patch_section", "id": id, "section": section, "action": "append",
            "content": Array(repeating: "filler", count: words).joined(separator: " ")
        ])
    }
    
    private func splitCandidateIds() throws -> [String] {
        try home.readScope { scope in
            try Candidates.splitCandidates(scope, limit: 50).map(\.id)
        }
    }
    
    private func dismissCount(noteId: String, kind: String) throws -> Int? {
        try home.read { database in
            try Int.fetchOne(database, sql: """
                SELECT dismiss_count FROM candidate_dismissals WHERE note_id = ? AND kind = ?
                """, arguments: [noteId, kind])
        }
    }
    
    private func lintIssues(code: String, includeDismissed: Bool = false) throws -> [Lint.Issue] {
        try home.readScope { scope in
            let all = try Lint.lintAll(scope)
            let visible = includeDismissed ? all : try Lint.suppressDismissed(scope, all)
            
            return visible.filter { issue in issue.code == code }
        }
    }
}
