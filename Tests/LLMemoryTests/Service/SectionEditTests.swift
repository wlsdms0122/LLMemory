//
//  SectionEditTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
@testable import LLMemory

@Suite("SectionEdit Tests")
struct SectionEditTests {
    // MARK: - Property
    private let nested = "## A\nintro of A\n\n### B\nbody B\n\n### C\nbody C\n"
    
    private let sectionEdit = SectionEdit()

    // MARK: - Initializer
    // MARK: - Test
    private func path(_ text: String) throws -> SectionEdit.SectionPath {
        try sectionEdit.parsePath(text)
    }
    
    // extract — overlapping/duplicate ranges throw (catchable) instead of trapping
    @Test("extracting the same section twice throws rather than silently taking it once")
    func extractDuplicateSectionsThrowsNotTrap() throws {
        // When
        let body = "## A\nbody A\n"
        
        // Then
        #expect(throws: SectionError.self) {
            _ = try sectionEdit.extract(body, paths: [try path("## A"), try path("## A")])
        }
    }
    
    @Test("extracting a section and its own child throws rather than taking the body twice")
    func extractNestedOverlapThrowsNotTrap() throws {
        // When
        let body = "## A\nintro\n### B\nbody B\n"
        
        // Then
        #expect(throws: SectionError.self) {
            _ = try sectionEdit.extract(body, paths: [try path("## A"), try path("## A > ### B")])
        }
    }
    
    @Test("extracting sections that do not overlap succeeds")
    func extractDisjointSectionsSucceeds() throws {
        // When
        let body = "## A\nbody A\n\n## B\nbody B\n"
        let (extracted, remaining) = try sectionEdit.extract(body, paths: [try path("## A"), try path("## B")])
        
        // Then
        #expect(extracted.contains("body A"))
        #expect(extracted.contains("body B"))
        #expect(!remaining.contains("body A"))
        #expect(!remaining.contains("body B"))
    }
    
    // replace
    @Test("replace touches the section it names and leaves its children in place")
    func replaceDefaultKeepsChildSections() throws {
        // When
        let out = try sectionEdit.replace(nested, path: path("## A"), newContent: "NEW intro")
        
        // Then
        #expect(out.contains("NEW intro"))
        #expect(!out.contains("intro of A"))
        #expect(out.contains("### B"))
        #expect(out.contains("body B"))
        #expect(out.contains("### C"))
        #expect(out.contains("body C"))
    }
    
    @Test("replace with subtree takes the children too — the caller asked for the whole branch")
    func replaceSubtreeWipesChildSections() throws {
        // When
        let out = try sectionEdit.replace(nested, path: path("## A"), newContent: "only A", subtree: true)
        
        // Then
        #expect(out.contains("only A"))
        #expect(!out.contains("### B"))
        #expect(!out.contains("### C"))
    }
    
    @Test("on a leaf the two modes agree, because there is no branch to differ over")
    func replaceLeafSectionUnaffectedByMode() throws {
        // When
        let leaf = "## A\nold body\n"
        let direct = try sectionEdit.replace(leaf, path: path("## A"), newContent: "new body")
        let subtree = try sectionEdit.replace(leaf, path: path("## A"), newContent: "new body", subtree: true)
        
        // Then
        #expect(direct == subtree)
        #expect(direct.contains("new body"))
        #expect(!direct.contains("old body"))
    }
    
    @Test("a child section can be addressed and replaced on its own")
    func replaceChildSectionDirectly() throws {
        // When
        let out = try sectionEdit.replace(nested, path: path("## A > ### B"), newContent: "patched B")
        
        // Then
        #expect(out.contains("patched B"))
        #expect(!out.contains("body B"))
        #expect(out.contains("body C"))
        #expect(out.contains("intro of A"))
    }
    
    // path parsing — `>` is a separator only before a heading marker
    @Test("an angle bracket inside a heading is part of the title, not a path separator")
    func parsePathKeepsLiteralAngleBracketInHeading() throws {
        // When
        let parsed = try path("## Ledger schema (`state/forge/jobs/<id>.json`)")
        
        // Then
        #expect(parsed.parts.count == 1)
        #expect(parsed.parts[0].title == "Ledger schema (`state/forge/jobs/<id>.json`)")
    }
    
    @Test("a real path separator still splits into parent and child")
    func parsePathStillSplitsNestedHeadings() throws {
        // When
        let parsed = try path("## A > ### B")
        
        // Then
        #expect(parsed.parts.count == 2)
        #expect(parsed.parts[0].title == "A")
        #expect(parsed.parts[1].title == "B")
    }
    
    @Test("a section whose title contains an angle bracket is still addressable")
    func replaceSectionWithAngleBracketHeading() throws {
        // When
        let body = "## Ledger schema (`jobs/<id>.json`)\nold schema\n"
        let out = try sectionEdit.replace(body, path: path("## Ledger schema (`jobs/<id>.json`)"), newContent: "new schema")
        
        // Then
        #expect(out.contains("new schema"))
        #expect(!out.contains("old schema"))
    }
    
    // remove
    @Test("removing a section that has children is refused unless the caller says subtree")
    func removeGuardsAgainstChildLoss() throws {
        // Then
        #expect(throws: SectionError.self) {
            _ = try sectionEdit.remove(nested, path: path("## A"))
        }
    }
    
    @Test("the refusal names the children that would have gone with it")
    func removeGuardErrorNamesSwallowedSections() throws {
        // Given
        do {
            _ = try sectionEdit.remove(nested, path: path("## A"))
        
        // When
            Issue.record("the guarded remove did not throw")
        } catch let error as SectionError {
            let message = error.description
        
        // Then
            #expect(message.contains("### B"))
            #expect(message.contains("### C"))
            #expect(message.contains("subtree"))
        }
    }
    
    @Test("remove with subtree drops the section and its children together")
    func removeSubtreeDropsWholeSection() throws {
        // When
        let out = try sectionEdit.remove(nested, path: path("## A"), subtree: true)
        
        // Then
        #expect(!out.contains("## A"))
        #expect(!out.contains("### B"))
        #expect(!out.contains("### C"))
    }
    
    @Test("removing a leaf needs no flag, because nothing goes with it")
    func removeLeafSectionNeedsNoFlag() throws {
        // When
        let body = "## A\nbody A\n\n## B\nbody B\n"
        let out = try sectionEdit.remove(body, path: path("## B"))
        
        // Then
        #expect(!out.contains("## B"))
        #expect(out.contains("## A"))
    }
    
    @Test("removing a child leaves its sibling and its parent alone")
    func removeChildSectionLeavesSiblingAndParent() throws {
        // When
        let out = try sectionEdit.remove(nested, path: path("## A > ### B"))
        
        // Then
        #expect(!out.contains("body B"))
        #expect(out.contains("### C"))
        #expect(out.contains("intro of A"))
    }
    
    // preamble
    @Test("the preamble is addressable, so a body with no headings can still be edited")
    func replacePreambleRewritesHeadingFreeBody() throws {
        // When
        let flat = "| id | desc |\n|---|---|\n| a | one |\n"
        let out = sectionEdit.replacePreamble(flat, newContent: "| id | desc |\n|---|---|\n| b | two |")
        
        // Then
        #expect(out.contains("| b | two |"))
        #expect(!out.contains("| a | one |"))
    }
    
    @Test("appending to the preamble of a heading-free body adds at the end")
    func appendPreambleHeadingFreeAddsAtEnd() throws {
        // When
        let flat = "| id | desc |\n|---|---|\n| a | one |\n"
        let out = sectionEdit.appendPreamble(flat, content: "| b | two |")
        
        // Then
        #expect(out.contains("| a | one |"))
        #expect(out.contains("| b | two |"))
        #expect(out.range(of: "| a | one |")!.lowerBound < out.range(of: "| b | two |")!.lowerBound)
    }
    
    @Test("a preamble edit leaves the heading sections untouched")
    func preambleEditsPreserveHeadingSections() throws {
        // When
        let body = "intro line\n\n## A\nbody A\n"
        let replaced = sectionEdit.replacePreamble(body, newContent: "new intro")
        
        // Then
        #expect(replaced.contains("new intro"))
        #expect(!replaced.contains("intro line"))
        #expect(replaced.contains("## A"))
        #expect(replaced.contains("body A"))
        
        let appended = sectionEdit.appendPreamble(body, content: "extra")
        
        #expect(appended.range(of: "extra")!.lowerBound < appended.range(of: "## A")!.lowerBound)
        #expect(appended.contains("intro line"))
    }
    
    @Test("prepending to the preamble inserts above what was there")
    func prependPreambleInsertsAtTop() throws {
        // When
        let body = "intro line\n\n## A\nbody A\n"
        let out = sectionEdit.prependPreamble(body, content: "header")
        
        // Then
        #expect(out.hasPrefix("header"))
        #expect(out.contains("intro line"))
        #expect(out.contains("## A"))
    }
    
    @Test("removing the preamble keeps the headings, and empties a note that was all preamble")
    func removePreambleKeepsHeadingsButEmptiesFlatNote() throws {
        // When
        let body = "intro line\n\n## A\nbody A\n"
        let kept = sectionEdit.removePreamble(body)
        
        // Then
        #expect(!kept.contains("intro line"))
        #expect(kept.contains("## A"))
        #expect(kept.contains("body A"))
        
        let flat = "just a line\nand another\n"
        
        #expect(sectionEdit.removePreamble(flat).isEmpty)
    }
    
    // append — direct body vs subtree (07-14 regression)
    @Test("append lands in the section it names, above its children")
    func appendDefaultLandsInDirectBody() throws {
        // When
        let out = try sectionEdit.append(nested, path: path("## A"), content: "appended-to-A")
        let appendedIndex = out.range(of: "appended-to-A")!.lowerBound
        let childIndex = out.range(of: "### B")!.lowerBound
        
        // Then
        #expect(appendedIndex < childIndex, "the default append belongs in the direct body, above the first child (### B) — got:\n\(out)")
    }
    
    @Test("appended text is attributed to the section that owns it, not to a child")
    func appendedTextAttributedToParentInSectionRows() throws {
        // When
        let out = try sectionEdit.append(nested, path: path("## A"), content: "zzmarker")
        let (_, rows) = sectionEdit.sectionRows(out)
        let parentRow = rows.first { row in row.path == "## A" }
        let childRow = rows.first { row in row.path == "## A > ### C" }
        
        // Then
        #expect(parentRow?.text.contains("zzmarker") == true, "the appended text belongs to row A — rows: \(rows.map { row in row.path })")
        #expect(childRow?.text.contains("zzmarker") != true, "it must not leak into the last child's row (### C)")
    }
    
    @Test("append with subtree lands after the children instead")
    func appendSubtreeLandsAfterChildren() throws {
        // When
        let out = try sectionEdit.append(nested, path: path("## A"), content: "tail-block", subtree: true)
        
        // Then
        #expect(out.range(of: "tail-block")!.lowerBound > out.range(of: "body C")!.lowerBound,
            "subtree=true must insert after the last child (### C) — got:\n\(out)")
    }
    
    @Test("with no children the two append modes agree")
    func appendChildlessSectionUnchangedAcrossModes() throws {
        // When
        let leaf = "## A\nbody A\n"
        let direct = try sectionEdit.append(leaf, path: path("## A"), content: "x")
        let subtree = try sectionEdit.append(leaf, path: path("## A"), content: "x", subtree: true)
        
        // Then
        #expect(direct == subtree, "with no children the two modes agree, so a flat-list append is unaffected")
    }
    
    // fence scanning — openers are matched, not toggled
    @Test("headings inside a nested example fence are text, not sections")
    func nestedExampleFenceDoesNotProjectSections() {
        // Given
        let body = """
        ## Real
        text

        ````
        ```swift
        ## Example
        ```
        ````
        """
        let titles = sectionEdit.splitSections(body).map { section in section.title }
        
        // Then
        #expect(titles == ["Real"], "an example heading inside a four-backtick fence was projected as a section: \(titles)")
        
        let mask = sectionEdit.fenceMask(body.unicodeLines())
        
        #expect(mask[3...7].allSatisfy { masked in masked }, "the whole fenced block must be masked: \(mask)")
    }
    
    @Test("a line that opens a fence with an info string does not close the one already open")
    func infoStringLineIsNotACloser() {
        // When
        let lines = ["```", "code", "```swift", "## Nope", "```"]
        let scan = sectionEdit.scanFences(lines)
        
        // Then
        #expect(scan.unclosedOpen == nil)
        #expect(scan.mask.allSatisfy { masked in masked }, "every line is inside the fence: \(scan.mask)")
    }
    
    @Test("a fence closes on an indented, length-matched pair and not before")
    func indentedAndLengthMatchedFences() {
        // When
        let lines = ["  ```json", "  # not a heading", "  ```", "# heading"]
        let scan = sectionEdit.scanFences(lines)
        
        // Then
        #expect(scan.mask == [true, true, true, false])
        #expect(scan.unclosedOpen == nil)
        
        let short = sectionEdit.scanFences(["~~~~", "~~~", "still inside", "~~~~"])
        
        #expect(short.unclosedOpen == nil)
        #expect(short.mask == [true, true, true, true])
    }
    
    @Test("the scanner reports a fence that never closed")
    func unclosedFenceIsReportedByTheScanner() {
        // When
        let scan = sectionEdit.scanFences(["intro", "```swift", "code", "## Nope"])
        
        // Then
        #expect(scan.unclosedOpen == 1)
        #expect(scan.mask == [false, true, true, true])
    }
    
    @Test("a backtick inside an info string does not open a fence")
    func backtickInfoStringIsNotAFence() {
        // When
        let scan = sectionEdit.scanFences(["```a``b", "## Heading"])
        
        // Then
        #expect(scan.mask == [false, false])
        #expect(scan.unclosedOpen == nil)
    }
}
