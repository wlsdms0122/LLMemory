//
//  BaseKnowledgeTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// The base knowledge a release ships. One sentence carries the whole contract —
// a base id always holds the shipped copy — so these tests are mostly about what
// is *not* here any more: no privileged directory, no state read as intent, no
// second command to explain the first.
@Suite("Base Knowledge Tests")
struct BaseKnowledgeTests {
    // MARK: - Property
    private let source = PackageSource()
    private let home: MemoryHome

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("the embedded seeds are byte-identical to the documents they were generated from")
    func embeddedSeedsMatchDocumentFiles() throws {
        // Given
        #expect(!Base.seeds.isEmpty, "no base documents embedded")

        for seed in Base.seeds {
            // When
            let onDisk = try String(contentsOf: seedFile(seed.id), encoding: .utf8)

            // Then
            #expect(onDisk == seed.markdown,
                "\(seedFile(seed.id).path) and Base.swift diverged — run tool/set-up.sh")
        }
    }

    // Every other test here iterates Base.seeds, so a document added without
    // rerunning tool/set-up.sh is a document nothing looks at. This walks the
    // other way — from the tree — and compares both directions, which is also
    // where a dotted file name actually gets caught: `a.b.md` derives the id
    // `a.b`, which no seed carries.
    @Test("the embedded set is exactly the document tree — nothing missing, nothing extra")
    func embeddedSeedsAreExactlyTheDocumentTree() throws {
        // Given
        let root = source.file("document/cortex")
        var onDisk = Set<String>()

        guard let walk = FileManager.default.enumerator(atPath: root.path) else {
            throw TestFailure("document/cortex is not readable at \(root.path)")
        }

        // When — the id is the location, derived here the way the generator derives it.
        for case let relative as String in walk where relative.hasSuffix(".md") {
            onDisk.insert(
                String(relative.dropLast(3)).replacingOccurrences(of: "/", with: ".")
            )
        }

        // Then
        let embedded = Set(Base.seeds.map(\.id))

        #expect(!onDisk.isEmpty, "no documents found under \(root.path)")
        #expect(onDisk.subtracting(embedded).isEmpty,
            "documents with no embedded seed — run tool/set-up.sh: \(onDisk.subtracting(embedded).sorted())")
        #expect(embedded.subtracting(onDisk).isEmpty,
            "embedded seeds with no document: \(embedded.subtracting(onDisk).sorted())")
    }

    @Test("every seed declares locked: true, so ops cannot rewrite the shipped copy")
    func everySeedIsLocked() throws {
        for seed in Base.seeds {
            // When
            let onDisk = try String(contentsOf: seedFile(seed.id), encoding: .utf8)

            // Then
            #expect(onDisk.contains("\nlocked: true\n"), "\(seed.id) must declare locked: true")
        }
    }

    @Test("a seed is addressed by where it is planted, and declares no id of its own")
    func seedDeclaresNoId() throws {
        for seed in Base.seeds {
            // When
            _ = try Frontmatter.parse(seed.markdown)

            // Then
            #expect(!seed.markdown.contains("\nid:"),
                "\(seed.id): the markdown still declares an id line")
        }
    }

    @Test("init plants the base knowledge as notes that can actually be retrieved")
    func initPlantsSeedsAsRetrievableNotes() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-base-init")

        for seed in Base.seeds {
            // When
            let planted = brain.file(Paths.relativeFile(forId: seed.id))
            let result = brain.run(["query", "get", seed.id, "--json"])

            // Then
            #expect(FileManager.default.fileExists(atPath: planted.path), "\(seed.id) not planted")
            #expect(result.succeeded, "planted note not retrievable: \(result.standardError)")
        }
    }

    @Test("a fresh brain holds exactly the shipped set and nothing else")
    func freshBrainHoldsOnlyTheBaseKnowledge() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-base-tree", seeded: false)

        // When
        let result = brain.run(["query", "tree", "--json"])
        let rows = result.jsonArrayOfArrays() ?? []
        let prefixes = Set(rows.compactMap { row in row.first as? String })

        // Then
        #expect(prefixes == Set(Base.seeds.compactMap { seed in Paths.branch(of: seed.id, depth: 1) }),
            "fresh brain tree: \(prefixes.sorted())")
    }

    // The shipped copy wins at a base id, always — that is the entire contract,
    // and it is why nothing needs to ask whether an edit was deliberate.
    @Test("an edited base note is restated, and the run says which id it rewrote")
    func updateRestatesAnEditedBaseNote() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-base-edit")
        let seed = try firstSeed()
        let file = brain.file(Paths.relativeFile(forId: seed.id))

        try (seed.markdown + "\nlocal addition.\n").write(to: file, atomically: true, encoding: .utf8)

        // When
        let result = brain.run(["update", "--json"])

        // Then
        let refreshed = result.jsonObject()?["refreshed"] as? [String] ?? []

        #expect(result.succeeded, "\(result.standardError)")
        #expect(refreshed.contains(seed.id), "an overwrite must be reported: \(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)
    }

    // Deleting the file used to mean "I opted out". It means nothing now — the
    // filesystem carries no intent, so a brain that does not want the base
    // knowledge says so on the command line instead.
    @Test("a deleted base note comes back on the next update")
    func updateReplantsADeletedBaseNote() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-base-delete")
        let seed = try firstSeed()
        let file = brain.file(Paths.relativeFile(forId: seed.id))

        try FileManager.default.removeItem(at: file)

        // When
        let result = brain.run(["update", "--json"])

        // Then
        let planted = result.jsonObject()?["planted"] as? [String] ?? []

        #expect(result.succeeded, "\(result.standardError)")
        #expect(planted.contains(seed.id), "update must replant: \(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)
    }

    @Test("--no-base leaves the base knowledge out — on init and on update alike")
    func noBaseSkipsPlanting() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-base-none", seeded: false, base: false)
        let seed = try firstSeed()
        let file = brain.file(Paths.relativeFile(forId: seed.id))

        #expect(!FileManager.default.fileExists(atPath: file.path), "--no-base must not plant")

        // When
        let result = brain.run(["update", "--no-base", "--json"])

        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(!FileManager.default.fileExists(atPath: file.path), "--no-base must not plant on update")

        // When — and the choice is per invocation, not a setting the brain keeps.
        let again = brain.run(["update", "--json"])

        #expect(again.succeeded, "\(again.standardError)")
        #expect(FileManager.default.fileExists(atPath: file.path),
            "a plain update must plant: \(again.standardOutput)")
    }

    // There is no system-managed directory any more, so a base note's neighbours
    // are ordinary notes — including the ones addressed underneath it.
    @Test("update touches base ids only — authored notes beside and beneath them are left alone")
    func updateLeavesAuthoredNotesAlone() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-base-scope")
        let seed = try firstSeed()
        let authored = brain.noteURL(id: "tech.di-container")
        let before = try String(contentsOf: authored, encoding: .utf8)
        let beneath = brain.file(Paths.relativeFile(forId: "\(seed.id).mine"))

        try FileManager.default.createDirectory(
            at: beneath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let mine = """
        ---
        title: mine
        priority: lazy
        tags: [flow]
        summary: authored under a base note's address
        ---

        ## Note
        not the release's.
        """

        try mine.write(to: beneath, atomically: true, encoding: .utf8)

        // When
        let result = brain.run(["update"])

        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(try String(contentsOf: authored, encoding: .utf8) == before)
        #expect(try String(contentsOf: beneath, encoding: .utf8) == mine,
            "a note under a base note's address is not the release's to touch")
    }

    @Test("a locked base note refuses an ops mutation")
    func baseNoteRefusesOpsMutation() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-base-locked")
        let seed = try firstSeed()

        // When
        let result = brain.applyOps("""
            {"ops":[{"op":"set_frontmatter","id":"\(seed.id)","fields":{"summary":"hijacked"}}],\
            "rationale":"test"}
            """)

        // Then
        #expect(!result.succeeded || result.jsonObject()?["status"] as? String == "rejected",
            "locked base note accepted an ops mutation: \(result.standardOutput)")
    }

    @Test("locked is a bot-mutation gate, not ownership — planting restates the note either way")
    func plantRestatesSeedRegardlessOfLocked() throws {
        // Given
        _ = Seeding.plant()

        let seed = try firstSeed()
        let file = Paths.file(forId: seed.id)
        let forked = seed.markdown.replacingOccurrences(of: "locked: true", with: "locked: false")
            + "\n## Local fork\nauthored by a person\n"

        try forked.write(to: file, atomically: true, encoding: .utf8)

        // When
        let result = Seeding.plant()

        // Then
        #expect(result.refreshed.contains(seed.id),
            "a base id is always the shipped copy, locked or not — got \(result)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)
    }

    // MARK: - Private
    // document/ holds the shipped subtree of a cortex, so a seed's document sits
    // at exactly the brain-relative path its id spells. Going through Paths rather
    // than repeating the mapping here makes that sameness the thing under test.
    private func seedFile(_ id: String) -> URL {
        source.file("document/\(Paths.relativeFile(forId: id))")
    }

    private func firstSeed() throws -> Base.Seed {
        guard let seed = Base.seeds.first else { throw TestFailure("no base documents embedded") }

        return seed
    }
}
