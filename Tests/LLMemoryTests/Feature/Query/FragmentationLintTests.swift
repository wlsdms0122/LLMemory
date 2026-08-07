//
//  FragmentationLintTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

// Splitting knowledge only helps if the pieces stay reachable. These rules watch for the two ways it
// goes wrong — a note that should have been split, and a family that was split but never linked.
@Suite("FragmentationLint Tests", .serialized)
struct FragmentationLintTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    @Test("an oversized note is reported, and the message hands over the command to read it in parts")
    func oversizedFiresOnLargeNoteAndCarriesNextHop() throws {
        // Given
        #expect(create("frag-big", content: Self.longBody()).status == "ok")
        #expect(create("frag-small", content: "## A\ntiny body\n").status == "ok")
        
        // When
        let issues = try lint(code: "note-oversized")
        
        // Then
        #expect(issues.map(\.target.subject) == ["frag-big"])
        #expect(issues[0].message.contains("--toc"),
            "the message must carry the next hop: \(issues[0].message)")
    }
    
    @Test("a note that accumulates dated sections is a growing buffer, whatever its current size")
    func growthFiresOnDatedSectionBuffer() throws {
        // Given
        #expect(create("frag-log", content: Self.datedSections(count: 10), axis: "journal").status == "ok")
        
        // Then
        #expect(try subjects(of: "growth-unbounded") == ["frag-log"])
    }
    
    @Test("growth is judged on structure, not on size — a small buffer trips growth but not size")
    func growthIsIndependentOfSize() throws {
        // Given
        #expect(create("frag-tinylog", content: Self.datedSections(count: 9, body: "x"), axis: "journal")
            .status == "ok")
        
        // Then
        #expect(try subjects(of: "growth-unbounded") == ["frag-tinylog"])
        #expect(try lint(code: "note-oversized").isEmpty, "a small buffer must not also trip the size rule")
    }
    
    @Test("a note whose id already carries its period is a sealed bucket, not a live buffer")
    func growthSkipsAlreadyRolledPeriodNotes() throws {
        // Given
        for noteId in ["frag-log-260701", "frag-log-260701-06", "frag-log-260701-06-am"] {
            #expect(create(noteId, content: Self.datedSections(count: 12), axis: "journal").status == "ok")
        }
        
        // Then
        #expect(try subjects(of: "growth-unbounded").isEmpty,
            "a period-stamped id is a rolled bucket, not a live buffer")
    }
    
    @Test("a date inside a section title is a topic, not a log entry")
    func growthIgnoresTopicalSections() throws {
        // Given
        let body = (1 ... 10).map { index in "## Background \(index) (decided 2026-07-01)\nprose\n" }.joined()
        
        #expect(create("frag-topics", content: body).status == "ok")
        
        // Then
        #expect(try subjects(of: "growth-unbounded").isEmpty)
    }
    
    @Test("an unlinked family is reported once for the family, not once per member")
    func fragmentUnlinkedFiresOncePerFamily() throws {
        // Given
        #expect(create("audit-run", content: "## Index\nthe list of runs\n").status == "ok")
        
        for suffix in ["alpha", "beta", "gamma", "delta"] {
            #expect(create("audit-run-\(suffix)", content: "## A\nbody\n").status == "ok")
        }
        
        // When
        let issues = try lint(code: "fragment-unlinked")
        
        // Then
        #expect(issues.count == 1, "expected one family finding, got \(issues.map(\.target.subject))")
        #expect(issues[0].message.contains("audit-run"))
        #expect(issues[0].message.contains("4/4"))
        #expect(try subjects(of: "gist-missing").isEmpty, "a family with a gist does not need one")
    }
    
    @Test("members that cite each other are reachable, so only the missing gist is reported")
    func fragmentSatisfiedByDeliberateSiblingLink() throws {
        // Given
        #expect(create("audit-run-alpha", content: "## A\nsee `audit-run-beta`\n").status == "ok")
        #expect(create("audit-run-beta", content: "## A\nsee `audit-run-alpha`\n").status == "ok")
        #expect(create("audit-run-gamma", content: "## A\nsee `audit-run-alpha`\n").status == "ok")
        
        // Then
        #expect(try subjects(of: "fragment-unlinked").isEmpty, "members that cite each other are reachable")
        #expect(try subjects(of: "gist-missing").count == 1,
            "a missing gist is a different failure from being isolated")
    }
    
    @Test("a name prefix shared across axes is coincidence, not a family")
    func fragmentIgnoresCrossAxisPrefixCoincidence() throws {
        // Given
        #expect(create("shared-name-one", content: "## A\nb\n", axis: "tech").status == "ok")
        #expect(create("shared-name-two", content: "## A\nb\n", axis: "journal").status == "ok")
        #expect(create("shared-name-three", content: "## A\nb\n", axis: "flow").status == "ok")
        
        // Then
        #expect(try subjects(of: "fragment-unlinked").isEmpty)
    }
    
    @Test("a single-segment stem is too weak a signal to call a family")
    func fragmentIgnoresSingleSegmentStem() throws {
        // Given
        for suffix in ["one", "two", "three"] {
            #expect(create("jineun-\(suffix)", content: "## A\nb\n").status == "ok")
        }
        
        // Then
        #expect(try subjects(of: "fragment-unlinked").isEmpty)
    }
    
    @Test("splitting plants the sibling edges itself, so a tool-made family is never born unlinked")
    func splitPlantsSiblingEdgesSoFamilyIsNeverBornUnlinked() throws {
        // Given
        #expect(create("frag-src", content: "## A\nalpha body\n## B\nbeta body\n## C\ngamma\n").status == "ok")
        
        // When
        let result = split(from: "frag-src", into: [
            ("frag-kid-a", "## A"), ("frag-kid-b", "## B"), ("frag-kid-c", "## C")
        ])
        
        // Then
        #expect(result.status == "ok", "\(result.error)")
        #expect(try siblingEdgeCount() == 3, "expected a sibling clique")
        #expect(try subjects(of: "fragment-unlinked").isEmpty,
            "a tool-made family must not be reported as unlinked")
        #expect(try subjects(of: "gist-missing").count == 1,
            "the clique must not silence the gist check")
    }
    
    @Test("a clique is one family — a longer shared prefix must not split it into a phantom sub-family")
    func siblingCliqueSuppressesPrefixSubFamily() throws {
        // Given
        #expect(create("audit-x", content: "## Map\nindex\n").status == "ok")
        #expect(create("audit-x-src", content: "## A\na\n## B\nb\n## C\nc\n## D\nd\n## E\ne\n").status == "ok")
        
        let names = ["core", "workflow-exec", "workflow-resolve", "workflow-validate", "misc"]
        let sections = ["## A", "## B", "## C", "## D", "## E"]
        
        // When
        let result = split(from: "audit-x-src", into: zip(names, sections).map { name, section in
            ("audit-x-\(name)", section)
        })
        
        // Then
        let gists = try lint(code: "gist-missing")
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(!gists.contains { issue in issue.message.contains("audit-x-workflow") },
            "clique members were re-grouped by a longer shared prefix: \(gists.map(\.message))")
    }
    
    @Test("a note that joins a clique's family by name but not by edge is judged and named")
    func unlinkedEpisodeBesideCliqueIsAbsorbedAndReported() throws {
        // Given
        #expect(create("audit-y-src", content: "## A\na\n## B\nb\n## C\nc\n").status == "ok")
        
        let result = split(from: "audit-y-src", into: [
            ("audit-y-a", "## A"), ("audit-y-b", "## B"), ("audit-y-c", "## C")
        ])
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(create("audit-y-history", content: "## A\nno links here\n").status == "ok")
        
        // When
        let issues = try lint(code: "fragment-unlinked")
        
        // Then
        #expect(issues.count == 1, "the absorbed member must be judged: \(issues.map(\.message))")
        #expect(issues[0].message.contains("audit-y-history"), "the unlinked member must be named")
    }
    
    @Test("two siblings are already a family — the edge is the evidence, so no stem floor applies")
    func graphFamilyNeedsOnlyTwoMembers() throws {
        // Given
        #expect(create("pair-src", content: "## A\nalpha\n## B\nbeta\n").status == "ok")
        
        let result = split(from: "pair-src", into: [("pair-src-one", "## A"), ("pair-src-two", "## B")])
        
        #expect(result.status == "ok", "\(result.error)")
        
        // When
        let families = try home.read { database in try FamilyView.families(database) }
        
        // Then
        #expect(families.contains { family in
            family.members.contains("pair-src-one") && family.members.contains("pair-src-two")
        }, "a sibling pair below the stem floor is still a family: \(families.map(\.members))")
    }
    
    @Test("a promotion is recorded as a fact at full weight, and only lineage kinds are accepted")
    func linkLineageRecordsPromotionAsFact() throws {
        // Given
        #expect(create("frag-principle", content: "## A\nthe principle\n").status == "ok")
        #expect(create("frag-episode", content: "## A\nthe run log\n", axis: "journal").status == "ok")
        
        // When
        let result = home.apply([
            "op": "link_lineage", "src": "frag-episode", "dst": "frag-principle",
            "kind": "promoted_to", "reason": "a repeated pattern extracted into a principle"
        ])
        let rejected = home.apply([
            "op": "link_lineage", "src": "frag-episode", "dst": "frag-principle", "kind": "assoc"
        ])
        
        // Then
        let weight = try home.read { database in
            try Double.fetchOne(database, sql: """
                SELECT weight FROM note_links WHERE src = ? AND dst = ? AND kind = 'promoted_to'
                """, arguments: ["frag-episode", "frag-principle"])
        }
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(weight == 1.0, "lineage is a fact — full weight, not a decaying proposal")
        #expect(rejected.status != "ok", "assoc is not a lineage kind")
    }
    
    @Test("the gist warning closes once an index note exists")
    func gistMissingClosesWhenIndexNoteExists() throws {
        // Given
        for suffix in ["one", "two", "three"] {
            #expect(create("audit-pass-\(suffix)", content: "## A\nb\n").status == "ok")
        }
        
        #expect(try subjects(of: "gist-missing") == ["audit-pass-one"])
        
        // When
        #expect(create("audit-pass", content: "## Index\n- one\n- two\n- three\n").status == "ok")
        
        // Then
        #expect(try subjects(of: "gist-missing").isEmpty)
    }
    
    @Test("sibling edges survive a rebuild — they are facts the tool planted, not derived data")
    func siblingEdgesSurviveRebuild() throws {
        // Given
        #expect(create("frag-rb", content: "## A\nalpha\n## B\nbeta\n").status == "ok")
        
        let result = split(from: "frag-rb", into: [("frag-rb-one", "## A"), ("frag-rb-two", "## B")])
        
        #expect(result.status == "ok", "\(result.error)")
        #expect(try siblingEdgeCount() == 1)
        
        // When
        _ = try Index.build(rebuild: true)
        
        // Then
        #expect(try siblingEdgeCount() == 1, "a rebuild must not erase sibling edges")
    }
    
    @Test("a corpus-scope warn can be reviewed and closed like any other")
    func corpusScopeWarnIsDismissible() throws {
        // Given
        for suffix in ["one", "two", "three"] {
            #expect(create("audit-corp-\(suffix)", content: "## A\nb\n").status == "ok")
        }
        
        #expect(try subjects(of: "gist-missing").count == 1)
        
        // When
        let dismissed = home.apply([
            "op": "dismiss_candidate", "id": "audit-corp-one", "kind": "lint:gist-missing",
            "reason": "only three runs so far — not grown enough to need a gist"
        ])
        
        // Then
        #expect(dismissed.status == "ok", "\(dismissed.error)")
        #expect(try subjects(of: "gist-missing").isEmpty)
    }
    
    @Test("dismissing in the same batch as an edit fails loud rather than keying off a moving shape")
    func dismissalInSameBatchAsAnEditFailsLoud() throws {
        // Given
        #expect(create("frag-batch", content: Self.longBody()).status == "ok")
        
        // When
        let result = home.apply([
            [
                "op": "patch_section", "id": "frag-batch", "section": "## A",
                "action": "replace", "content": "short"
            ],
            ["op": "dismiss_candidate", "id": "frag-batch", "kind": "lint:note-oversized"]
        ])
        
        // Then
        #expect(result.status != "ok", "an absent write-time shape must fail, not fall back to a blanket key")
    }
    
    @Test("a reviewed warning goes quiet, and --include-dismissed still shows it")
    func dismissedWarnIsSuppressedUntilShapeDiverges() throws {
        // Given
        #expect(create("frag-keep", content: Self.longBody()).status == "ok")
        #expect(try subjects(of: "note-oversized") == ["frag-keep"])
        
        // When
        let dismissed = home.apply([
            "op": "dismiss_candidate", "id": "frag-keep", "kind": "lint:note-oversized",
            "reason": "one coherent narrative — its size is the size of the concept"
        ])
        
        // Then
        #expect(dismissed.status == "ok", "\(dismissed.error)")
        #expect(try subjects(of: "note-oversized").isEmpty, "a reviewed warning must stop surfacing")
        #expect(try lint(code: "note-oversized", includeDismissed: true).map(\.target.subject) == ["frag-keep"])
    }
    
    @Test("with several findings of one code, the dismissal must say which one")
    func multipleFindingsOfOneCodeRequireSelection() throws {
        // Given
        #expect(create("frag-target-one", content: "## A\nb\n").status == "ok")
        #expect(create("frag-target-two", content: "## A\nb\n").status == "ok")
        #expect(create("frag-refs", content: "## A\nsee `frag-target-onx` and `frag-target-twx`\n")
            .status == "ok")
        
        let live = try lint(id: "frag-refs", code: "dangling-note-ref")
        
        #expect(live.count == 2, "the fixture must produce two findings, got \(live.map(\.message))")
        
        // When
        let blanket = home.apply([
            "op": "dismiss_candidate", "id": "frag-refs", "kind": "lint:dangling-note-ref"
        ])
        let picked = home.apply([
            "op": "dismiss_candidate", "id": "frag-refs", "kind": "lint:dangling-note-ref",
            "finding": "frag-target-onx", "reason": "a false positive on a code symbol"
        ])
        
        // Then
        let remaining = try lint(id: "frag-refs", code: "dangling-note-ref")
        
        #expect(blanket.status != "ok", "a code-wide dismissal must be refused when two findings exist")
        #expect(picked.status == "ok", "\(picked.error)")
        #expect(remaining.count == 1, "the sibling finding must survive: \(remaining.map(\.message))")
        #expect(remaining[0].message.contains("frag-target-twx"))
    }
    
    @Test("a selector that matches no live finding is refused rather than silently doing nothing")
    func unmatchedFindingSelectorIsRefused() throws {
        // Given
        #expect(create("frag-sel", content: Self.longBody()).status == "ok")
        
        // When
        let result = home.apply([
            "op": "dismiss_candidate", "id": "frag-sel", "kind": "lint:note-oversized",
            "finding": "no such phrase"
        ])
        
        // Then
        #expect(result.status != "ok")
    }
    
    @Test("an error code cannot be dismissed — an integrity violation is not a matter of opinion")
    func errorCodesAreNotDismissible() throws {
        // Given
        #expect(create("frag-e", content: "## A\nb\n").status == "ok")
        
        // When
        let result = home.apply([
            "op": "dismiss_candidate", "id": "frag-e", "kind": "lint:axis-mismatch", "reason": "nope"
        ])
        
        // Then
        #expect(result.status != "ok", "an error code must be refused")
        #expect(result.error.contains("error"), "the refusal should say why: \(result.error)")
    }
    
    @Test("an unknown lint code is refused rather than recorded against nothing")
    func unknownLintCodeIsRefused() throws {
        // Given
        #expect(create("frag-u", content: "## A\nb\n").status == "ok")
        
        // When
        let result = home.apply([
            "op": "dismiss_candidate", "id": "frag-u", "kind": "lint:no-such-rule", "reason": "x"
        ])
        
        // Then
        #expect(result.status != "ok")
    }
    
    // MARK: - Private
    private static func longBody() -> String {
        "## A\n" + Array(repeating: "word", count: 2500).joined(separator: " ") + "\n"
    }
    
    private static func datedSections(count: Int, body: String = "entry") -> String {
        (1 ... count)
            .map { day in "## 2026-07-\(String(format: "%02d", day))\n\(body)\n" }
            .joined()
    }
    
    @discardableResult
    private func create(_ id: String, content: String, axis: String = "tech") -> Transaction.Result {
        home.createNote(id: id, axis: axis, tags: [axis, "frag"], content: content)
    }
    
    @discardableResult
    private func split(from source: String, into children: [(id: String, section: String)]) -> Transaction.Result {
        home.apply([
            "op": "split_note",
            "from_id": source,
            "into": children.map { child in
                [
                    "id": child.id, "axis": "tech", "title": child.id, "tags": ["tech"],
                    "summary": "summary", "sections": [child.section]
                ] as [String: Any]
            }
        ])
    }
    
    private func lint(id: String? = nil, code: String, includeDismissed: Bool = false) throws -> [Lint.Issue] {
        try QueryFeature.lint(home: home.path, id: id, code: code, includeDismissed: includeDismissed)
    }
    
    private func subjects(of code: String) throws -> [String] {
        try lint(code: code).map(\.target.subject)
    }
    
    private func siblingEdgeCount() throws -> Int {
        try home.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM note_links WHERE kind = ?",
                arguments: [Links.kindSibling]
            ) ?? 0
        }
    }
}
