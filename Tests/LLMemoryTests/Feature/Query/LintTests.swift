//
//  LintTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Lint is an observation layer, not an enforcement one. An error names a broken invariant; a warning
// asks for a judgement and has to hand over enough to make it.
@Suite("Lint Tests", .serialized)
struct LintTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("a well-formed note reports no path collision")
    func cleanNoteNoCollisionIssue() throws {
        // Given
        #expect(create("tlint-clean", content: "## A\nbody\n## B\nbody more\n").status == "ok")
        
        // Then
        #expect(!(try codes(of: "tlint-clean").contains("path-collision")))
    }
    
    @Test("two sections on one path are an error, and the path is named")
    func collisionSurfacesAsError() throws {
        // Given
        create("tlint-broken", content: "## ok\nbody\n")
        
        try home.overwriteBody(of: "tlint-broken", with: "## A\nfoo\n## A\nbar\n")
        
        // When
        let collisions = try issues(of: "tlint-broken").filter { issue in issue.code == "path-collision" }
        
        // Then
        #expect(collisions.count == 1)
        #expect(collisions[0].severity == "error")
        #expect(collisions[0].message.contains("## A"))
    }
    
    @Test("a body whose only searchable token is a compound identifier is thin on retrieval terms")
    func enrichThinFiresForKoreanBodyWithCompoundIdentifier() throws {
        // Given
        create("tlint-enrich-thin", content: "## 구조\n3개 PIIMaskingTransformer 가 마스킹한다.\n")
        
        // Then
        #expect(try issues(of: "tlint-enrich-thin")
            .contains { issue in issue.code == "enrich-thin" && issue.severity == "warn" })
    }
    
    @Test("a short ASCII token is a word, not a bare identifier — it does not make a body thin")
    func enrichThinSkipsShortAsciiTokens() throws {
        // Given
        create("tlint-ios", content: "## 구조\niOS 로그 마스킹 동작.\n")
        
        // Then
        #expect(!(try codes(of: "tlint-ios").contains("enrich-thin")))
    }
    
    @Test("near-duplicate tags are reported as a measured fact, not as a typo verdict")
    func tagNearDuplicateReportsFactNotTypoVerdict() throws {
        // Given
        for index in 1 ... 3 { createTagged("td-a-\(index)", tags: ["transfer"]) }
        for index in 1 ... 3 { createTagged("td-b-\(index)", tags: ["transfor"]) }
        
        // When
        let match = try allIssues().first { issue in
            issue.code == "tag-near-duplicate"
                && issue.message.contains("transfer") && issue.message.contains("transfor")
        }
        
        // Then
        #expect(match != nil)
        #expect(match?.message.contains("edit-distance") == true,
            "the message must carry the measurement behind the claim")
    }
    
    @Test("a tag too short to measure is skipped rather than guessed at")
    func tagNearDuplicateSkipsShortTags() throws {
        // Given
        createTagged("ts-a", tags: ["ci"])
        createTagged("ts-b", tags: ["cli"])
        
        // Then
        #expect(!(try allIssues().contains { issue in
            issue.code == "tag-near-duplicate" && issue.message.contains("'ci'")
        }))
    }
    
    @Test("two ticket ids that differ by a digit are enumerable, not near-duplicates")
    func tagNearDuplicateSkipsEnumerableIds() throws {
        // Given
        createTagged("ti-a", tags: ["bki-303"])
        createTagged("ti-b", tags: ["bki-353"])
        
        // Then
        #expect(!(try allIssues().contains { issue in
            issue.code == "tag-near-duplicate" && issue.message.contains("bki-303")
        }))
    }
    
    @Test("lint filters by code and severity, and a limit cuts the most severe findings first")
    func lintFiltersByCodeSeverityLimit() throws {
        // Given
        create("lf-enrich", content: "## 구조\nPIIMaskingTransformer 가 마스킹.\n")
        create("lf-broken", content: "## ok\nbody\n")
        
        try home.overwriteBody(of: "lf-broken", with: "## A\nx\n## A\ny\n")
        
        // When
        let all = try home.readScope { db in try home.lintScanner.scan(
                db,
                id: nil,
                code: nil,
                severity: nil,
                limit: nil,
                includeDismissed: false
            )
        }
        let errors = try home.readScope { db in try home.lintScanner.scan(
                db,
                id: nil,
                code: nil,
                severity: "error",
                limit: nil,
                includeDismissed: false
            )
        }
        let onlyEnrich = try home.readScope { db in try home.lintScanner.scan(
                db,
                id: nil,
                code: "enrich-thin",
                severity: nil,
                limit: nil,
                includeDismissed: false
            )
        }
        let capped = try home.readScope { db in try home.lintScanner.scan(
                db,
                id: nil,
                code: nil,
                severity: nil,
                limit: 1,
                includeDismissed: false
            )
        }
        
        // Then
        #expect(all.contains { issue in issue.severity == "error" })
        #expect(all.contains { issue in issue.code == "enrich-thin" })
        #expect(!errors.isEmpty)
        #expect(errors.allSatisfy { issue in issue.severity == "error" })
        #expect(!onlyEnrich.isEmpty)
        #expect(onlyEnrich.allSatisfy { issue in issue.code == "enrich-thin" })
        #expect(capped.count == 1)
        #expect(capped.first?.severity == "error", "a limit must keep the most severe finding")
    }
    
    @Test("an unclosed fence is an error, and the line it opened on is named")
    func fenceUnclosedIsError() throws {
        // Given
        create("tlint-fence", content: "## A\nok body\n")
        
        try home.overwriteBody(of: "tlint-fence", with: "## A\n```json\n{\"x\": 1}\n")
        
        // When
        let found = try issues(of: "tlint-fence").filter { issue in issue.code == "fence-unclosed" }
        
        // Then
        #expect(found.count == 1)
        #expect(found[0].severity == "error")
        #expect(found[0].message.contains("line 2"))
    }
    
    @Test("text inside a closed fence is code, so neither the fence nor the hash rule fires")
    func closedFenceWithHashInsideIsClean() throws {
        // Given
        create("tlint-fence2", content: "## A\n```sh\n#comment\n```\nbody text\n")
        
        // Then
        let found = try codes(of: "tlint-fence2")
        
        #expect(!found.contains("fence-unclosed"))
        #expect(!found.contains("bare-hash-line"))
    }
    
    @Test("a line that opens with a hash reads as a heading — a channel name is flagged")
    func bareHashLineFlagsChannelName() throws {
        // Given
        create("tlint-hash", content: "## A\n#team-transfer-dev-bank channel digest\n")
        
        // When
        let found = try issues(of: "tlint-hash").filter { issue in issue.code == "bare-hash-line" }
        
        // Then
        #expect(found.count == 1)
        #expect(found[0].severity == "warn")
    }
    
    @Test("a heading that skips a level is reported with the jump it made")
    func headingSkipFlagsLevelJump() throws {
        // Given
        create("tlint-skip", content: "## A\nbody one\n#### B\ndeep body\n")
        
        // Then
        #expect(try issues(of: "tlint-skip")
            .contains { issue in issue.code == "heading-skip" && issue.message.contains("h2→h4") })
    }
    
    @Test("a heading immediately followed by another suggests its content was displaced")
    func adjacentEmptyHeadingSignalsDisplacedContent() throws {
        // Given
        create("tlint-adj", content: "## A\n## B\nreal body here\n")
        create("tlint-adj2", content: "## A\n\n## B\nreal body here\n")
        
        // When
        let adjacent = try issues(of: "tlint-adj")
        let spaced = try issues(of: "tlint-adj2")
        
        // Then
        #expect(adjacent.contains { issue in
            issue.code == "adjacent-empty-heading" && issue.message.contains("## A")
        })
        #expect(!spaced.contains { issue in issue.code == "adjacent-empty-heading" },
            "a blank line between them is deliberate spacing, not displacement")
        #expect(spaced.contains { issue in issue.code == "empty-section" })
    }
    
    @Test("a declared source that is not on disk is reported with the path it named")
    func staleSourceFlagsMissingAbsolutePath() throws {
        // Given
        create("tlint-src", content: "## A\nbody text\n")
        
        home.apply([
            "op": "set_frontmatter", "id": "tlint-src",
            "fields": ["source": ["/nonexistent/kernel/src/x.py"]]
        ])
        
        // Then
        #expect(try issues(of: "tlint-src")
            .contains { issue in issue.code == "stale-source" && issue.message.contains("/nonexistent/") })
    }
    
    @Test("a reference to an id that no longer exists names the nearest surviving one", arguments: [
        ("tlint-ref", "## A\nsee `skill-forge-dispatch` for detail.\n"),
        ("tlint-ref-wiki", "## A\nsee [[skill-forge-dispatch]] for detail.\n")
    ])
    func danglingNoteRefFlagsSplitResidue(noteId: String, body: String) throws {
        // Given
        create("skill-forge-dispatch-basic", content: "## A\ndispatch runbook body\n")
        create(noteId, content: body)
        
        // When
        let found = try issues(of: noteId).filter { issue in issue.code == "dangling-note-ref" }
        
        // Then
        #expect(found.count == 1)
        #expect(found[0].message.contains("skill-forge-dispatch-basic"))
    }
    
    @Test("a backticked token that resembles no note id is code, not a dangling reference")
    func danglingNoteRefIgnoresUnrelatedTokens() throws {
        // Given
        create("tlint-ref2", content: "## A\ncontrolled by the `apns-collapse-id` parameter.\n")
        
        // Then
        #expect(!(try codes(of: "tlint-ref2").contains("dangling-note-ref")))
    }
    
    @Test("the nearest id is decided the same way every call, and ambiguity resolves to nothing")
    func nearestIdIsDeterministicAcrossMultipleCandidates() {
        // Given
        let candidates: Set<String> = ["ref-target-aa", "ref-target-ab", "ref-targe", "unrelated-note"]
        
        // Then
        for _ in 0 ..< 50 {
            #expect(DanglingNoteRefRule().nearestId("ref-target", candidates, excluding: "self-note") == "ref-targe",
                "an edit-distance-1 candidate must beat an extension, and must do so every call")
        }
        
        #expect(DanglingNoteRefRule().nearestId("ref-target", ["ref-target-aa"], excluding: "x") == "ref-target-aa")
        #expect(DanglingNoteRefRule().nearestId("ref-target", ["ref-target-aa", "ref-target-ab"], excluding: "x") == nil,
            "two equally near candidates is not an answer")
        #expect(DanglingNoteRefRule().nearestId("ref-targex", ["ref-targea", "ref-targeb"], excluding: "x") == "ref-targea")
    }
    
    @Test("a document-db warning is dismissible like any other warning")
    func documentWarnIsDismissible() throws {
        // Given
        create("doc-target", content: "## A\nbody\n")
        create("doc-src", content: "## A\nsee [[doc-target]]\n")
        
        #expect(try codes(of: "doc-src").contains("wikilink-style"))
        
        // When
        let result = home.apply([
            "op": "dismiss_candidate", "id": "doc-src", "kind": "lint:wikilink-style",
            "reason": "reviewed, keeping"
        ])
        
        // Then
        #expect(result.status == "ok",
            "a document-db warn was refused as an unknown kind — \(result.error)")
    }
    
    @Test("the catalog's warnings and the dismissal gate come from the same registration")
    func catalogAndDismissGateAgree() {
        // When
        let catalogWarns = Set(
            home.lintScanner.ruleCatalog().filter { rule in rule.severity == "warn" }.map(\.code)
        )
        
        // Then
        #expect(catalogWarns == home.lintScanner.dismissibleCodes,
            "the catalog advertises a warning the dismissal gate does not accept, or the reverse")
    }
    
    @Test("a tag that drifts from its alias in frontmatter is reported with the canonical name")
    func tagAliasViolationFlagsFrontmatterDrift() throws {
        // Given
        createTagged("ta-a", tags: ["bangsong"])
        
        home.apply([
            "op": "rename_tag", "from_tag": "bangsong", "to_tag": "bangsongyi", "add_alias": true
        ])
        
        #expect(!(try codes(of: "ta-a").contains("tag-alias-violation")),
            "the rename itself must leave the note clean")
        
        // When — the frontmatter is edited back to the aliased spelling.
        let file = try home.indexedPath(of: "ta-a")
        let text = try String(contentsOf: file, encoding: .utf8)
        
        try text.replacingOccurrences(of: "bangsongyi", with: "bangsong")
            .write(to: file, atomically: true, encoding: .utf8)
        
        let found = try issues(of: "ta-a").filter { issue in issue.code == "tag-alias-violation" }
        
        // Then
        #expect(found.count == 1)
        #expect(found[0].message.contains("bangsongyi"), "the message must name the canonical tag")
    }
    
    @Test("isolation is judged on live neighbours — a stale neighbour is still a connection")
    func isolatedLintSeesThroughDeadEdges() throws {
        // Given
        for noteId in ["iso-x", "iso-y"] {
            let result = home.createNote(id: noteId, tags: ["tech"], content: "## A\nbody\n")
            
            #expect(result.status == "ok", "failed to create \(noteId): \(result.error)")
        }
        
        try home.database().write { database in
            try database.execute(sql: "DELETE FROM entity_index WHERE note_id = 'iso-x'")
        }
        
        // Then
        #expect(!(try isolatedSubjects().contains("iso-x")),
            "a note with a live neighbour was reported as isolated")
        
        // When
        try home.database().write { database in
            try database.execute(sql: "UPDATE notes SET stale = 1 WHERE id = 'iso-y'")
        }
        
        // Then
        #expect(!(try isolatedSubjects().contains("iso-x")),
            "a stale neighbour is still a connection — it must not read as isolation")
    }
    
    // MARK: - Private
    @discardableResult
    private func create(_ id: String, content: String, tag: String = "tech") -> OperationsResult {
        home.createNote(id: id, tags: [tag, "test"], content: content)
    }
    
    @discardableResult
    private func createTagged(_ id: String, tags: [String]) -> OperationsResult {
        home.createNote(id: id, tags: ["tech"] + tags, content: "## A\nx body\n")
    }
    
    private func issues(of noteId: String) throws -> [LintIssue] {
        try home.readScope { db in try home.lintScanner.lintNote(db, nid: noteId) }
    }
    
    private func codes(of noteId: String) throws -> Set<String> {
        Set(try issues(of: noteId).map(\.code))
    }
    
    private func allIssues() throws -> [LintIssue] {
        try home.readScope { db in try home.lintScanner.lintAll(db) }
    }
    
    private func isolatedSubjects() throws -> [String] {
        try home.readScope { db in try home.lintScanner.scan(
                db,
                id: nil,
                code: "isolated",
                severity: nil,
                limit: nil,
                includeDismissed: false
            )
        }.map(\.target.subject)
    }
}
