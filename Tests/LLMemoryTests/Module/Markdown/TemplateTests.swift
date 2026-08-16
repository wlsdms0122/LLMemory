//
//  TemplateTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("Template Tests", .serialized)
struct TemplateTests {
    // MARK: - Property
    private let home: MemoryHome
    static let templateBody = """
    # Background
    Project background.
    # Spec
    Detail.
    ## Task
    Task list.
    ## API
    Server API.
    ## Test
    Test.
    # Reference
    Reference.
    """
    
    private let sectionEdit = SectionEdit()

    private let frontmatter = Frontmatter()

    private let template = Template()

    private var detector: CandidateDetector { CandidateDetector(brain: home.brain) }

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    
    // engine (pure, no DB)
    @Test("parsing a template separates the frame it declares from the guidance beside it")
    func parseFrameExtractsGuideAndTree() {
        // When
        let frame = template.parseFrame(Self.templateBody)
        
        // Then
        #expect(frame.map(\.title) == ["Background", "Spec", "Reference"])
        #expect(frame[0].guide == "Project background.")
        
        let spec = frame[1]
        
        #expect(spec.children.map(\.title) == ["Task", "API", "Test"])
        #expect(spec.children[0].guide == "Task list.")
    }
    
    @Test("a marker-looking character at the end of a heading is part of the title")
    func literalTrailingMarkerCharsAreHeadingText() {
        // When
        let frame = template.parseFrame("# Spec\n## Open?\nx\n")
        
        // Then
        #expect(frame[0].children[0].title == "Open?")
        #expect(template.validate(documentBody: "# Spec\n## Open?\ny\n", frame: frame) == nil)
        #expect(template.validate(documentBody: "# Spec\n", frame: frame) != nil)
    }
    
    @Test("heading matching normalizes numbering, bullets and case, so cosmetics do not break a frame")
    func normalizeStripsNumberingBulletsAndCase() {
        // Then
        #expect(template.normalize("API") == "api")
        #expect(template.normalize("1. API") == "api")
        #expect(template.normalize("① 개요") == "개요")
        #expect(template.normalize("- 항목") == "항목")
        #expect(template.normalize("  Spec  ") == "spec")
    }
    
    @Test("a document that follows the frame validates")
    func validateAcceptsConformingDoc() {
        // When
        let frame = template.parseFrame(Self.templateBody)
        let document = """
        # Background
        filler
        # Spec
        ## Task
        - a
        ## API
        x
        ## Test
        t
        # Reference
        z
        """
        
        // Then
        #expect(template.validate(documentBody: document, frame: frame) == nil)
    }
    
    @Test("a heading that only normalizes to the same thing is still a different heading")
    func validateRejectsNormalizedButInexactHeadings() {
        // When
        let frame = template.parseFrame(Self.templateBody)
        let numbered = """
        # Background
        b
        # Spec
        ## 1. Task
        - a
        ## API
        x
        ## Test
        t
        # Reference
        z
        """
        let numberedError = template.validate(documentBody: numbered, frame: frame)
        
        // Then
        #expect(numberedError != nil && numberedError!.contains("완전일치"),
            "numbering is refused and the exact form is offered — got \(String(describing: numberedError))")
        
        let wrongLevel = """
        # Background
        b
        # Spec
        ### Task
        - a
        ## API
        x
        ## Test
        t
        # Reference
        z
        """
        
        #expect(template.validate(documentBody: wrongLevel, frame: frame) != nil,
            "a heading at the wrong level must be refused")
        
        let document = """
        # Background
        b
        # Spec
        ## Task
        - a
        ## API
        x
        ## Test
        t
        # Reference
        z
        """
        
        #expect(template.validate(documentBody: document, frame: frame) == nil)
        
        let sections = sectionEdit.splitSections(document)
        let hit = sections.first { section in section.level == 2 && section.title == "Task" }
        
        #expect(hit != nil, "whatever the frame declares must stay addressable by (level, title)")
    }
    
    @Test("a missing frame section is refused — every declared heading is required")
    func validateRejectsMissingSection() {
        // When
        let frame = template.parseFrame(Self.templateBody)
        let document = "# Background\nx\n# Spec\n## Task\nt\n## API\na\n# Reference\nr\n"
        let error = template.validate(documentBody: document, frame: frame)
        
        // Then
        #expect(error != nil)
        #expect(error!.contains("Test"))
    }
    
    @Test("a heading the frame does not declare is refused at frame level")
    func validateRejectsForeignFrameLevelHeading() {
        // When
        let frame = template.parseFrame(Self.templateBody)
        let document = "# Background\nx\n# Spec\n## Task\nt\n## API\na\n## Test\nq\n# Chatter\nz\n# Reference\nr\n"
        let error = template.validate(documentBody: document, frame: frame)
        
        // Then
        #expect(error != nil)
        #expect(error!.contains("외래"))
    }
    
    @Test("deeper headings and empty sections are the author's business, not the frame's")
    func validateAllowsDeeperHeadingsAndEmptySections() {
        // When
        let frame = template.parseFrame(Self.templateBody)
        let document = "# Background\n# Spec\n## Task\n### free sub\nfree\n## API\n## Test\n# Reference\n"
        
        // Then
        #expect(template.validate(documentBody: document, frame: frame) == nil)
    }
    
    @Test("the frame's order is part of the frame")
    func validateRejectsReorderedFrame() {
        // When
        let frame = template.parseFrame(Self.templateBody)
        let document = "# Spec\n## Task\nt\n## API\na\n## Test\nq\n# Background\nb\n# Reference\nr\n"
        
        // Then
        #expect(template.validate(documentBody: document, frame: frame) != nil)
    }
    
    @Test("a template whose own siblings collide is refused as a malformed frame")
    func duplicateSiblingNormRejectedAsMalformedFrame() {
        // When
        let frame = template.parseFrame("# Spec\n## 1. Step\n## 2. Step\n")
        let error = template.validate(documentBody: "# Spec\n## 1. Step\nx\n", frame: frame)
        
        // Then
        #expect(error != nil)
        #expect(error!.contains("중복 섹션"))
    }
    
    @Test("a scaffold emits every declared section and validates against the frame it came from")
    func scaffoldEmitsAllSectionsAndValidates() {
        // When
        let frame = template.parseFrame(Self.templateBody)
        let body = template.scaffold(frame)
        
        // Then
        for heading in ["# Background", "# Spec", "## Task", "## API", "## Test", "# Reference"] {
            #expect(body.contains(heading))
        }
        
        #expect(template.validate(documentBody: body + "\n", frame: frame) == nil)
    }
    
    // ops integration
    private func makeTemplate(locked: Bool = true) -> OperationsResult {
        OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "tpl-spec", "axis": "template",
            "title": "Spec template", "summary": "s", "tags": ["template"],
            "content": Self.templateBody, "locked": locked
        ]], "rationale": "test"])
    }
    
    private func body(_ home: MemoryHome, _ id: String) throws -> String {
        let queue = try home.storage.connect()
        let relative = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT 1 FROM notes WHERE id = ?", arguments: [id]).map { _ in home.layout.relativeFile(forId: id) }
        }
        let text = try String(contentsOf: home.url.appendingPathComponent(relative!), encoding: .utf8)
        
        return try frontmatter.parse(text).1
    }
    
    @Test("creating a document with a template and no content scaffolds the whole frame")
    func documentWithTemplateScaffoldsFullFrame() throws {
        // Then
        #expect(makeTemplate().status == "ok")
        
        let created = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "doc-1", "axis": "flow",
            "title": "document", "summary": "s", "tags": ["flow"], "template": "tpl-spec"
        ]], "rationale": "test"])
        
        #expect(created.status == "ok")
        
        let scaffolded = try body(home, "doc-1")
        
        for heading in ["# Background", "## Task", "## API", "## Test", "# Reference"] {
            #expect(scaffolded.contains(heading))
        }
        
        let queue = try home.storage.connect()
        let row = try queue.read { db in
            try Row.fetchOne(db, sql: "SELECT template, locked FROM notes WHERE id = 'doc-1'")
        }
        
        #expect((row?["template"] as String?) == "tpl-spec")
        #expect((row?["locked"] as Int?) == 0)
    }
    
    @Test("a document naming a template that does not exist is refused")
    func unknownTemplateRejected() throws {
        // When
        let created = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "doc-x", "axis": "flow",
            "title": "document", "summary": "s", "tags": ["flow"], "template": "tpl-missing",
            "content": "# Background\nx\n"
        ]], "rationale": "test"])
        
        // Then
        #expect(created.status == "rejected")
        #expect(created.error.contains("unknown template"))
    }
    
    @Test("a locked note refuses an ops mutation — it is edited by a person, not by the bot")
    func lockedNoteRefusesOpsMutation() throws {
        // Then
        #expect(makeTemplate().status == "ok")
        
        let result = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "patch_section", "id": "tpl-spec",
            "section": "# Background", "action": "append", "content": "x"
        ]], "rationale": "test"])
        
        #expect(result.status == "rejected")
        #expect(result.error.contains("locked"))
    }
    
    @Test("an edit that stays inside the frame succeeds")
    func patchWithinFrameSucceeds() throws {
        // Then
        #expect(makeTemplate().status == "ok")
        
        _ = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "doc-2", "axis": "flow",
            "title": "document", "summary": "s", "tags": ["flow"], "template": "tpl-spec"
        ]], "rationale": "test"])
        
        let result = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "patch_section", "id": "doc-2",
            "section": "# Spec > ## Task", "action": "append", "content": "- an implementation item"
        ]], "rationale": "test"])
        
        #expect(result.status == "ok")
        #expect(try body(home, "doc-2").contains("- an implementation item"))
    }
    
    @Test("an edit that breaks the frame rolls back")
    func breakingFrameRollsBack() throws {
        // Then
        #expect(makeTemplate().status == "ok")
        
        _ = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "doc-3", "axis": "flow",
            "title": "document", "summary": "s", "tags": ["flow"], "template": "tpl-spec"
        ]], "rationale": "test"])
        
        let result = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "patch_section", "id": "doc-3", "section": "# Spec > ## Task", "action": "remove"
        ]], "rationale": "test"])
        
        #expect(result.status == "failed")
        #expect(result.error.contains("template frame"))
        #expect(try body(home, "doc-3").contains("## Task"))
    }
    
    @Test("a create carrying a section outside the frame rolls back")
    func foreignSectionOnCreateRollsBack() throws {
        // Then
        #expect(makeTemplate().status == "ok")
        
        let created = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "doc-4", "axis": "flow",
            "title": "document", "summary": "s", "tags": ["flow"], "template": "tpl-spec",
            "content": "# Background\nx\n# Spec\n## Task\nt\n## API\na\n## Test\nq\n# Chatter\nz\n# Reference\nr\n"
        ]], "rationale": "test"])
        
        #expect(created.status == "failed")
        #expect(created.error.contains("template frame"))
        
        let queue = try home.storage.connect()
        
        #expect(try !queue.read { db in try NoteExistsTransaction(nid: "doc-4").perform(db) })
    }
    
    @Test("editing a template revalidates the documents bound to it")
    func editingTemplateRevalidatesBoundDocuments() throws {
        // Then
        #expect(makeTemplate(locked: false).status == "ok")
        
        _ = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "doc-dep", "axis": "flow",
            "title": "document", "summary": "s", "tags": ["flow"], "template": "tpl-spec"
        ]], "rationale": "test"])
        
        let result = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "patch_section", "id": "tpl-spec", "section": "# Reference",
            "action": "append", "content": "# Rollout\nthe rollout procedure."
        ]], "rationale": "test"])
        
        #expect(result.status == "failed")
        #expect(result.error.contains("template frame"))
        #expect(try !body(home, "tpl-spec").contains("Rollout"))
    }
    
    @Test("a document that has drifted can still be deleted — the frame guards edits, not exits")
    func deleteDriftedDocumentSucceeds() throws {
        // Then
        #expect(OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "tpl-ab", "title": "t",
            "summary": "s", "tags": ["template"],
            "content": "# A\nguidance A.\n# B\nguidance B.", "locked": true
        ]], "rationale": "t"]).status == "ok")
        #expect(OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "doc-d", "title": "d",
            "summary": "s", "tags": ["flow"], "template": "tpl-ab",
            "content": "# A\nx\n# B\ny\n"
        ]], "rationale": "t"]).status == "ok")
        
        let queue = try home.storage.connect()
        let relative = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT 1 FROM notes WHERE id='tpl-ab'").map { _ in home.layout.relativeFile(forId: "tpl-ab") }
        }
        let templateFile = home.url.appendingPathComponent(relative!)
        let text = try String(contentsOf: templateFile, encoding: .utf8)
        
        try (text + "# C\nguidance C.\n").write(to: templateFile, atomically: true, encoding: .utf8)
        
        _ = try home.storage.writeLock { try queue.write { db in try ReindexNoteFileTransaction(noteId: try home.brain.requireNoteId(of: templateFile), path: templateFile).perform(db) } }
        
        let result = OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "delete_note", "id": "doc-d", "reason": "drift cleanup"
        ]], "rationale": "t"])
        
        #expect(result.status == "ok")
        #expect(try !queue.read { db in try NoteExistsTransaction(nid: "doc-d").perform(db) })
    }
    
    @Test("a templated or locked note is not a reorganisation candidate")
    func clusterCandidatesExcludeDocumentsAndLocked() throws {
        // Then
        #expect(makeTemplate().status == "ok")
        
        for id in ["cl-n1", "cl-n2"] {
            #expect(OperationsEngine.apply(home.storage, home.brain, ["ops": [[
                "op": "create_note", "id": id, "title": "t", "summary": "s",
                "tags": ["flow"], "content": "## A\nx\n", "entities": ["ClusterEnt"]
            ]], "rationale": "t"]).status == "ok")
        }
        
        #expect(OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "cl-doc", "title": "d", "summary": "s",
            "tags": ["flow"], "template": "tpl-spec", "entities": ["ClusterEnt"]
        ]], "rationale": "t"]).status == "ok")
        #expect(OperationsEngine.apply(home.storage, home.brain, ["ops": [[
            "op": "create_note", "id": "cl-lk", "title": "l", "summary": "s",
            "tags": ["flow"], "content": "## A\ny\n", "locked": true, "entities": ["ClusterEnt"]
        ]], "rationale": "t"]).status == "ok")
        
        let queue = try home.storage.connect()
        let members = Set(try queue.read { db in try detector.clusters(GRDBReadScope(db)) }.flatMap { cluster in cluster.members.map(\.id) })
        
        #expect(members.contains("cl-n1"))
        #expect(members.contains("cl-n2"))
        #expect(!members.contains("cl-doc"))
        #expect(!members.contains("cl-lk"))
    }
    
    @Test("querying a template returns the frame plus the guidance for each section")
    func queryTemplateReturnsFrameSchema() throws {
        // Then
        #expect(makeTemplate().status == "ok")
        
        let (note, frame, _) = try home.readScope { scope in try home.notesService.template(scope, id: "tpl-spec", sessionId: nil) }
        
        #expect(note.id == "tpl-spec")
        #expect(frame.map(\.title) == ["Background", "Spec", "Reference"])
    }
}
