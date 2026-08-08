//
//  SourceVerifyInvariantTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
import GRDB
@testable import LLMemory

@Suite("SourceVerifyInvariant Tests", .serialized)
struct SourceVerifyInvariantTests {
    // MARK: - Property
    private let home: MemoryHome
    
    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }
    
    // MARK: - Test
    
    // the baseline is an observation: only rebase (declaration change / ack) may move it
    private static func writeSourcedNote(_ id: String, source: URL, body: String = "# body") throws -> URL {
        let directory = Paths.notes.appendingPathComponent("flow")
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let path = directory.appendingPathComponent("\(id).md")
        
        try """
        ---
        id: \(id)
        title: t
        axis: flow
        priority: lazy
        tags: [flow]
        summary: s
        source: ["\(source.path)"]
        ---

        \(body)
        """.write(to: path, atomically: true, encoding: .utf8)
        
        return path
    }
    
    private static func sourceRow(_ queue: any DatabaseWriter, _ id: String) throws -> (hash: String, stale: Int)? {
        try queue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT source_hash, source_stale FROM note_source WHERE note_id = ?",
                arguments: [id]) else { return nil }
            
            return (row["source_hash"], row["source_stale"])
        }
    }
    
    @Test("losing one of several sources is detected even when the modification times look fresh")
    func partialSourceDeletionIsDetectedDespiteFreshMtime() throws {
        // Given
        let first = home.url.appendingPathComponent("s1.txt")
        let second = home.url.appendingPathComponent("s2.txt")
        
        try "alpha".write(to: first, atomically: true, encoding: .utf8)
        try "beta".write(to: second, atomically: true, encoding: .utf8)
        
        let noteDirectory = Paths.notes.appendingPathComponent("flow")
        
        try FileManager.default.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
        
        let notePath = noteDirectory.appendingPathComponent("src-1.md")
        let markdown = """
        ---
        id: src-1
        title: t
        axis: flow
        priority: lazy
        tags: [flow]
        summary: s
        source: ["\(first.path)", "\(second.path)"]
        ---

        # body
        """
        
        try markdown.write(to: notePath, atomically: true, encoding: .utf8)
        
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        
        let future = 9_999_999_999
        
        try queue.write { db in
            try db.execute(sql: "UPDATE note_source SET source_checked_at = ? WHERE note_id = 'src-1'",
                arguments: [future])
        }
        
        // When
        let before = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_stale FROM note_source WHERE note_id = 'src-1'") ?? -1
        }
        
        // Then
        #expect(before == 0)
        
        try FileManager.default.removeItem(at: second)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: future) }
        
        let after = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_stale FROM note_source WHERE note_id = 'src-1'") ?? -1
        }
        
        #expect(after == 1, "partial source deletion stayed falsely fresh (mtime fast-path skipped the fingerprint recompute)")
    }
    
    @Test("a change to a file that is not the newest one is still a change")
    func nonMaxFileChangeIsDetected() throws {
        // Given
        let fileManager = FileManager.default
        let older = home.url.appendingPathComponent("old.txt")
        let newer = home.url.appendingPathComponent("new.txt")
        
        try "alpha".write(to: older, atomically: true, encoding: .utf8)
        try "beta".write(to: newer, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: older.path)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000)], ofItemAtPath: newer.path)
        
        let noteDirectory = Paths.notes.appendingPathComponent("flow")
        
        try fileManager.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
        
        let notePath = noteDirectory.appendingPathComponent("src-nm.md")
        
        try """
        ---
        id: src-nm
        title: t
        axis: flow
        priority: lazy
        tags: [flow]
        summary: s
        source: ["\(older.path)", "\(newer.path)"]
        ---

        # body
        """.write(to: notePath, atomically: true, encoding: .utf8)
        
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        try "alpha-changed".write(to: older, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_500_000)], ofItemAtPath: older.path)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db) }
        
        // When
        let stale = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_stale FROM note_source WHERE note_id = 'src-nm'") ?? -1
        }
        
        // Then
        #expect(stale == 1, "a change to a non-newest file was hidden behind the max(mtime) fast path")
    }
    
    @Test("a reference that is not a file has nothing to drift from, so it is not tracked")
    func opaqueRefsAreNotDriftTracked() throws {
        // Given
        let noteDirectory = Paths.notes.appendingPathComponent("flow")
        
        try FileManager.default.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
        
        let notePath = noteDirectory.appendingPathComponent("src-url.md")
        
        try """
        ---
        id: src-url
        title: t
        axis: flow
        priority: lazy
        tags: [flow]
        summary: s
        source: ["https://tossbank.slack.com/archives/C0/p1", "2026-06-25", "app/runner/x.py"]
        ---

        # body
        """.write(to: notePath, atomically: true, encoding: .utf8)
        
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        
        // When
        let rows = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_source WHERE note_id = 'src-url'") ?? -1
        }
        
        // Then
        #expect(rows == 0, "URL/date/relative-only sources must not create a note_source row")
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        let stale = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_source WHERE note_id = 'src-url' AND source_stale = 1") ?? -1
        }
        
        #expect(stale == 0, "opaque refs were falsely flagged source_stale")
    }
    
    @Test("in a mixed declaration only the file part is tracked for drift")
    func mixedSourceTracksOnlyTheFile() throws {
        // Given
        let grounding = home.url.appendingPathComponent("g.txt")
        
        try "alpha".write(to: grounding, atomically: true, encoding: .utf8)
        
        let noteDirectory = Paths.notes.appendingPathComponent("flow")
        
        try FileManager.default.createDirectory(at: noteDirectory, withIntermediateDirectories: true)
        
        let notePath = noteDirectory.appendingPathComponent("src-mix.md")
        
        try """
        ---
        id: src-mix
        title: t
        axis: flow
        priority: lazy
        tags: [flow]
        summary: s
        source: ["\(grounding.path)", "https://example.com/x"]
        ---

        # body
        """.write(to: notePath, atomically: true, encoding: .utf8)
        
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        
        // When
        let tracked = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_source WHERE note_id = 'src-mix'") ?? -1
        }
        
        // Then
        #expect(tracked == 1, "a mixed set with one absolute path must be drift-tracked")
        
        try FileManager.default.removeItem(at: grounding)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        let stale = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT source_stale FROM note_source WHERE note_id = 'src-mix'") ?? -1
        }
        
        #expect(stale == 1, "deleting the only checkable file should mark the note stale")
    }
    
    @Test("reindexing does not rebaseline the drift signal — it reads, it does not decide")
    func reindexDoesNotRebaselineDriftSignal() throws {
        // Given
        let file = home.url.appendingPathComponent("s.txt")
        
        try "v1".write(to: file, atomically: true, encoding: .utf8)
        
        let notePath = try Self.writeSourcedNote("src-keep", source: file)
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        
        // When
        let baseline = try Self.sourceRow(queue, "src-keep")
        
        // Then
        #expect(baseline?.stale == 0)
        
        try "v2 drifted".write(to: file, atomically: true, encoding: .utf8)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        #expect(try Self.sourceRow(queue, "src-keep")?.stale == 1)
        
        let raw = try String(contentsOf: notePath, encoding: .utf8)
        
        try (raw + "\nunrelated edit\n").write(to: notePath, atomically: true, encoding: .utf8)
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        
        let after = try Self.sourceRow(queue, "src-keep")
        
        #expect(after?.stale == 1, "note upsert must not silently ack source drift")
        #expect(after?.hash == baseline?.hash, "note upsert must not re-baseline the fingerprint")
    }
    
    @Test("a rebuild preserves the drift signal rather than clearing it by regenerating")
    func rebuildPreservesDriftSignal() throws {
        // Given
        let file = home.url.appendingPathComponent("s.txt")
        
        try "v1".write(to: file, atomically: true, encoding: .utf8)
        
        let notePath = try Self.writeSourcedNote("src-rb", source: file)
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        
        let baseline = try Self.sourceRow(queue, "src-rb")
        
        try "v2 drifted".write(to: file, atomically: true, encoding: .utf8)
        
        // When
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        // Then
        #expect(try Self.sourceRow(queue, "src-rb")?.stale == 1)
        
        try queue.write { db in
            try NoteArtifacts.snapshotForRebuild(db)
            try db.execute(sql: "DELETE FROM notes")
            
            _ = try Notes.reindexFile(db, path: notePath)
            
            try NoteArtifacts.restoreAfterRebuild(db)
        }
        
        let after = try Self.sourceRow(queue, "src-rb")
        
        #expect(after?.stale == 1, "rebuild must not swallow the drift signal")
        #expect(after?.hash == baseline?.hash, "rebuild must restore the observed baseline")
    }
    
    @Test("rebase_source is the op that rebaselines, and it clears the signal")
    func rebaseSourceRebaselinesAndClears() throws {
        // Given
        let file = home.url.appendingPathComponent("s.txt")
        
        try "v1".write(to: file, atomically: true, encoding: .utf8)
        
        let notePath = try Self.writeSourcedNote("src-ack", source: file)
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        
        // When
        let early = OpsEngine.apply(home.storage, ["ops": [["op": "rebase_source", "id": "src-ack", "reason": "r"]], "rationale": "t"])
        
        // Then
        #expect(early.status == "ok", "rebase of a fresh source must be allowed: \(early.error)")
        
        try "v2 drifted".write(to: file, atomically: true, encoding: .utf8)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        let before = try Self.sourceRow(queue, "src-ack")
        
        #expect(before?.stale == 1)
        
        let result = OpsEngine.apply(home.storage, ["ops": [["op": "rebase_source", "id": "src-ack", "reason": "reconciled"]], "rationale": "t"])
        
        #expect(result.status == "ok", "rebase failed: \(result.error)")
        
        let after = try Self.sourceRow(queue, "src-ack")
        
        #expect(after?.stale == 0, "rebase must clear source_stale")
        #expect(after?.hash != before?.hash, "rebase must move the baseline to the current file")
        
        let plainPath = Paths.notes.appendingPathComponent("flow/src-plain.md")
        
        try """
        ---
        id: src-plain
        title: t
        axis: flow
        priority: lazy
        tags: [flow]
        summary: s
        ---

        # body
        """.write(to: plainPath, atomically: true, encoding: .utf8)
        try queue.write { db in _ = try Notes.reindexFile(db, path: plainPath) }
        
        let none = OpsEngine.apply(home.storage, ["ops": [["op": "rebase_source", "id": "src-plain", "reason": "r"]], "rationale": "t"])
        
        #expect(none.status != "ok", "rebase without a note_source row must be refused")
    }
    
    @Test("changing the declaration through set_frontmatter rebaselines it")
    func setFrontmatterSourceChangeRebaselines() throws {
        // Given
        let first = home.url.appendingPathComponent("s1.txt")
        let second = home.url.appendingPathComponent("s2.txt")
        
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)
        
        let notePath = try Self.writeSourcedNote("src-decl", source: first)
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        try "one drifted".write(to: first, atomically: true, encoding: .utf8)
        
        // When
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        // Then
        #expect(try Self.sourceRow(queue, "src-decl")?.stale == 1)
        
        let result = OpsEngine.apply(home.storage, ["ops": [["op": "set_frontmatter", "id": "src-decl",
            "fields": ["source": [second.path]]]], "rationale": "t"])
        
        #expect(result.status == "ok", "set_frontmatter failed: \(result.error)")
        
        let after = try Self.sourceRow(queue, "src-decl")
        
        #expect(after?.stale == 0, "a new declaration is a new baseline — no inherited stale")
        
        let expected = try queue.read { _ in NoteSources.computeFingerprint([second.path]) }
        
        #expect(after?.hash == expected, "baseline must be the new declaration's fingerprint")
    }
    
    @Test("a split child that inherits the declaration inherits the observation with it")
    func splitInheritsObservationForInheritedDeclaration() throws {
        // Given
        let file = home.url.appendingPathComponent("s.txt")
        
        try "v1".write(to: file, atomically: true, encoding: .utf8)
        
        let notePath = try Self.writeSourcedNote("src-sp", source: file,
            body: "## A\nalpha\n## B\nbeta\n")
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        try "v2 drifted".write(to: file, atomically: true, encoding: .utf8)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        // When
        let parent = try Self.sourceRow(queue, "src-sp")
        
        // Then
        #expect(parent?.stale == 1)
        
        let into: [[String: Any]] = [
            ["id": "src-sp-a", "axis": "flow", "title": "A", "tags": ["flow"], "summary": "s", "sections": ["## A"]],
            ["id": "src-sp-b", "axis": "flow", "title": "B", "tags": ["flow"], "summary": "s", "sections": ["## B"]]
        ]
        let result = OpsEngine.apply(home.storage, ["ops": [["op": "split_note", "from_id": "src-sp", "into": into]], "rationale": "t"])
        
        #expect(result.status == "ok", "split failed: \(result.error)")
        
        for childId in ["src-sp-a", "src-sp-b"] {
            let child = try Self.sourceRow(queue, childId)
            
            #expect(child?.stale == 1, "\(childId): inherited declaration must inherit source_stale")
            #expect(child?.hash == parent?.hash, "\(childId): inherited declaration must inherit the baseline")
        }
    }
    
    @Test("a merge that changes the declaration rebaselines it")
    func mergeSourceChangeRebaselines() throws {
        // Given
        let first = home.url.appendingPathComponent("s1.txt")
        let second = home.url.appendingPathComponent("s2.txt")
        
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)
        
        let intoPath = try Self.writeSourcedNote("src-mi", source: first)
        let queue = try home.storage.connect()
        
        // When
        try queue.write { db in _ = try Notes.reindexFile(db, path: intoPath) }
        
        // Then
        #expect(home.createNote(id: "src-mf", content: "## F\nfrom body\n").status == "ok")
        
        try "one drifted".write(to: first, atomically: true, encoding: .utf8)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        #expect(try Self.sourceRow(queue, "src-mi")?.stale == 1)
        
        let result = OpsEngine.apply(home.storage, ["ops": [[
            "op": "merge_notes", "into_id": "src-mi", "from_ids": ["src-mf"],
            "merged_content": "## body\nmerged\n", "summary": "s", "tags": ["flow"],
            "source": [second.path]
        ]], "rationale": "t"])
        
        #expect(result.status == "ok", "merge failed: \(result.error)")
        
        let after = try Self.sourceRow(queue, "src-mi")
        
        #expect(after?.stale == 0, "an authored declaration change re-baselines")
        
        let expected = try queue.read { _ in NoteSources.computeFingerprint([second.path]) }
        
        #expect(after?.hash == expected, "baseline must be the merged declaration's fingerprint")
    }
    
    @Test("restating the same declaration does not clear drift — nothing was re-observed")
    func setFrontmatterSameSourceDoesNotClearDrift() throws {
        // Given
        let file = home.url.appendingPathComponent("s.txt")
        
        try "v1".write(to: file, atomically: true, encoding: .utf8)
        
        let notePath = try Self.writeSourcedNote("src-same", source: file)
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        try "v2 drifted".write(to: file, atomically: true, encoding: .utf8)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        // When
        let before = try Self.sourceRow(queue, "src-same")
        
        // Then
        #expect(before?.stale == 1)
        
        let result = OpsEngine.apply(home.storage, ["ops": [["op": "set_frontmatter", "id": "src-same",
            "fields": ["summary": "updated", "source": [file.path]]]], "rationale": "t"])
        
        #expect(result.status == "ok", "set_frontmatter failed: \(result.error)")
        
        let after = try Self.sourceRow(queue, "src-same")
        
        #expect(after?.stale == 1, "unchanged declaration must not launder the drift signal")
        #expect(after?.hash == before?.hash, "unchanged declaration must not move the baseline")
    }
    
    @Test("a child restating the same declaration inherits the observation rather than starting blank")
    func splitRestatedSameSourceInheritsObservation() throws {
        // Given
        let file = home.url.appendingPathComponent("s.txt")
        
        try "v1".write(to: file, atomically: true, encoding: .utf8)
        
        let notePath = try Self.writeSourcedNote("src-rs", source: file,
            body: "## A\nalpha\n## B\nbeta\n")
        let queue = try home.storage.connect()
        
        try queue.write { db in _ = try Notes.reindexFile(db, path: notePath) }
        try "v2 drifted".write(to: file, atomically: true, encoding: .utf8)
        
        _ = try queue.write { db in try NoteSources.bulkVerify(db, now: 9_999_999_999) }
        
        // When
        let parent = try Self.sourceRow(queue, "src-rs")
        
        // Then
        #expect(parent?.stale == 1)
        
        let into: [[String: Any]] = [
            ["id": "src-rs-a", "axis": "flow", "title": "A", "tags": ["flow"], "summary": "s",
                "sections": ["## A"], "source": [file.path]],
            ["id": "src-rs-b", "axis": "flow", "title": "B", "tags": ["flow"], "summary": "s",
                "sections": ["## B"]]
        ]
        let result = OpsEngine.apply(home.storage, ["ops": [["op": "split_note", "from_id": "src-rs", "into": into]], "rationale": "t"])
        
        #expect(result.status == "ok", "split failed: \(result.error)")
        
        for childId in ["src-rs-a", "src-rs-b"] {
            let child = try Self.sourceRow(queue, childId)
            
            #expect(child?.stale == 1, "\(childId): same declaration must inherit source_stale")
            #expect(child?.hash == parent?.hash, "\(childId): same declaration must inherit the baseline")
        }
    }
    
    @Test("only an ops handler may rebaseline — no read path is allowed to")
    func rebaseAuthorityIsConfinedToOpsHandlers() throws {
        // When
        let allowed: Set<String> = ["Service/Sources.swift",
            "Module/DB/Ops/HandlersBasic.swift",
            "Module/DB/Ops/HandlersStructural.swift"]
        let root = PackageSource().file("Sources/LLMemory")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { element in element as? URL }
            .filter { url in url.pathExtension == "swift" } ?? []
        
        // Then
        #expect(!files.isEmpty)
        
        var violations: [String] = []
        
        let rootPath = root.path + "/"
        
        for file in files where !allowed.contains(file.path.replacingOccurrences(of: rootPath, with: "")) {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            
            for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                var line = String(rawLine)
                
                if let comment = line.range(of: "//") { line = String(line[..<comment.lowerBound]) }
                
                if line.contains(".rebase(") || line.contains(".inheritObservation(") {
                    violations.append("\(file.lastPathComponent):\(offset + 1)  \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        
        #expect(violations.isEmpty, """
            re-baselining authority outside the ops handlers — the index pass may only project \
            (NoteSources.projectRefs):
            \(violations.joined(separator: "\n"))
            """)
    }
}
