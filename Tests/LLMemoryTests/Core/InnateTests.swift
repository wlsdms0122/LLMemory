//
//  InnateTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

@Suite("Innate Tests")
struct InnateTests {
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
        #expect(!Innate.seeds.isEmpty, "no innate seeds embedded")

        for seed in Innate.seeds {
            // When
            let onDisk = try String(contentsOf: seedFile(seed.id), encoding: .utf8)

            // Then
            #expect(onDisk == seed.markdown,
                "document/innate/\(seed.id).md and Innate.swift diverged — run tool/set-up.sh")
        }
    }

    @Test("every seed declares locked: true, so ops cannot rewrite the shipped copy")
    func everySeedIsLocked() throws {
        for seed in Innate.seeds {
            // When
            let onDisk = try String(contentsOf: seedFile(seed.id), encoding: .utf8)

            // Then
            #expect(onDisk.contains("\nlocked: true\n"), "\(seed.id) must declare locked: true")
        }
    }

    @Test("every seed is addressed under innate and its frontmatter agrees with its id")
    func seedFrontmatterAgreesWithId() throws {
        for seed in Innate.seeds {
            // When
            let (fields, _) = try Frontmatter.parse(seed.markdown)

            // Then
            #expect(fields.id == seed.id, "\(seed.id): frontmatter id mismatch (\(fields.id))")
            #expect(seed.id.hasPrefix("innate."),
                "\(seed.id): an innate seed is addressed under innate")
        }
    }

    @Test("init plants each seed under cortex/innate/ as a note that can actually be retrieved")
    func initPlantsSeedsAsRetrievableNotes() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-init")

        for seed in Innate.seeds {
            // When
            let planted = brain.file(Paths.relativeFile(forId: seed.id))
            let result = brain.run(["query", "get", seed.id, "--json"])

            // Then
            #expect(FileManager.default.fileExists(atPath: planted.path), "\(seed.id) not planted in cortex/innate")
            #expect(result.succeeded, "seeded note not retrievable: \(result.standardError)")
        }
    }

    @Test("a fresh brain owns exactly the innate branch and nothing else")
    func freshBrainOwnsOnlyTheInnateBranch() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-tree", seeded: false)

        // When
        let result = brain.run(["query", "tree", "--json"])
        let rows = result.jsonArrayOfArrays() ?? []
        let prefixes = rows.compactMap { row in row.first as? String }

        // Then
        #expect(prefixes == ["innate"], "fresh brain tree: \(prefixes)")
    }

    @Test("re-running init keeps a local edit to a seed — init plants what is missing, nothing more")
    func reinitKeepsLocalSeedEdit() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-reinit")
        let seed = try firstSeed()
        let file = brain.file(Paths.relativeFile(forId: seed.id))
        let edited = seed.markdown + "\nlocal addition.\n"

        try edited.write(to: file, atomically: true, encoding: .utf8)

        // When
        let result = brain.run(["init"])

        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(try String(contentsOf: file, encoding: .utf8) == edited,
            "init must not clobber a local seed edit")
    }

    @Test("a drifted seed blocks update — warned, untouched, exit 1; --override restates it")
    func updateBlocksOnDriftAndOverrideRestates() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-update")
        let seed = try firstSeed()
        let file = brain.file(Paths.relativeFile(forId: seed.id))
        let edited = seed.markdown + "\nlocal addition.\n"

        try edited.write(to: file, atomically: true, encoding: .utf8)

        // When — plain update must warn and keep its hands off.
        let result = brain.run(["update", "--json"])

        // Then
        #expect(!result.succeeded, "drift must exit 1")
        #expect(result.jsonObject()?["blocked"] as? Bool == true, "\(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == edited, "update must not touch a drifted seed")

        // When — --override restates the shipped copy.
        let overridden = brain.run(["update", "--override", "--json"])
        let refreshed = overridden.jsonObject()?["refreshed"] as? [String] ?? []

        // Then
        #expect(overridden.succeeded, "\(overridden.standardError)")
        #expect(refreshed.contains(seed.id), "--override must report the refresh: \(overridden.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)
    }

    @Test("a missing seed file (directory kept) blocks update — --override replants it")
    func updateBlocksOnMissingSeedAndOverrideReplants() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-repair")
        let seed = try firstSeed()
        let file = brain.file(Paths.relativeFile(forId: seed.id))

        try FileManager.default.removeItem(at: file)

        // When — plain update warns; the deletion may have been deliberate.
        let warned = brain.run(["update", "--json"])

        // Then
        #expect(!warned.succeeded, "a missing seed is drift — update must exit 1")
        #expect(!FileManager.default.fileExists(atPath: file.path), "warned update must not replant")

        // When
        let result = brain.run(["update", "--override", "--json"])
        let planted = result.jsonObject()?["planted"] as? [String] ?? []

        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(planted.contains(seed.id), "--override must replant: \(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)
    }

    @Test("deleting the whole innate/ directory opts the brain out — update skips, even after a reindex")
    func updateSkipsWhenDirectoryIsGone() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-optout")
        let directory = brain.file("cortex/innate")

        try FileManager.default.removeItem(at: directory)

        // When
        let result = brain.run(["update", "--json"])

        // Then
        let skipped = result.jsonObject()?["skipped"] as? [String] ?? []

        #expect(result.succeeded, "\(result.standardError)")
        #expect(skipped.contains(try firstSeed().id), "update must report the skip: \(result.standardOutput)")
        #expect(!FileManager.default.fileExists(atPath: directory.path), "the opt-out was overridden")

        // The opt-out must hold after the reindex settles the catalog too.
        #expect(brain.run(["index", "build"]).succeeded)

        let again = brain.run(["update", "--json"])

        #expect(again.succeeded, "\(again.standardError)")
        #expect(!FileManager.default.fileExists(atPath: directory.path), "the opt-out was overridden on the second update")
    }

    @Test("update --override replants the innate space into an opted-out brain")
    func updateOverrideReadoptsInnateSpace() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-override")
        let seed = try firstSeed()
        let file = brain.file(Paths.relativeFile(forId: seed.id))

        try FileManager.default.removeItem(at: brain.file("cortex/innate"))

        #expect(brain.run(["update"]).succeeded, "the opted-out update must pass")

        // When
        let result = brain.run(["update", "--override", "--json"])

        // Then
        let planted = result.jsonObject()?["planted"] as? [String] ?? []

        #expect(result.succeeded, "\(result.standardError)")
        #expect(planted.contains(seed.id), "--override must replant: \(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)

        let got = brain.run(["query", "get", seed.id, "--json"])

        #expect(got.succeeded, "replanted seed not retrievable: \(got.standardError)")
    }

    @Test("init --bare starts with nothing — no innate directory, and update honors the absence")
    func bareInitSkipsInnateSpace() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-bare", seeded: false, bare: true)
        let directory = brain.file("cortex/innate")

        #expect(!FileManager.default.fileExists(atPath: directory.path), "--bare must not plant")

        // When
        let result = brain.run(["update", "--json"])

        // Then
        let skipped = result.jsonObject()?["skipped"] as? [String] ?? []

        #expect(result.succeeded, "\(result.standardError)")
        #expect(skipped.contains(try firstSeed().id), "update must skip a bare brain: \(result.standardOutput)")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("update --check reports drift with exit 1 and writes nothing")
    func updateCheckReportsDriftWithoutWriting() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-check")
        let seed = try firstSeed()
        let file = brain.file(Paths.relativeFile(forId: seed.id))

        // A clean brain matches the shipped copy.
        let clean = brain.run(["update", "--check", "--json"])

        #expect(clean.succeeded, "clean check must exit 0: \(clean.standardError)")
        #expect(clean.jsonObject()?["drift"] as? Bool == false, "\(clean.standardOutput)")

        let edited = seed.markdown + "\nlocal addition.\n"

        try edited.write(to: file, atomically: true, encoding: .utf8)

        // When
        let result = brain.run(["update", "--check", "--json"])

        // Then
        let refreshed = result.jsonObject()?["refreshed"] as? [String] ?? []

        #expect(!result.succeeded, "drift must exit 1")
        #expect(refreshed.contains(seed.id), "check must name the drifted seed: \(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == edited, "check must not write")
    }

    @Test("a note the release does not ship is reported as foreign — and never touched")
    func foreignFileIsReportedNotTouched() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-foreign")
        let stranger = brain.file("cortex/innate/hand-planted.md")
        let content = """
        ---
        id: innate.hand-planted
        title: hand planted
        priority: lazy
        tags: [innate]
        summary: a human put this here
        ---

        ## Note
        not shipped by any release.
        """

        try content.write(to: stranger, atomically: true, encoding: .utf8)

        // When — check must call it drift; a plain update must warn and leave it alone.
        let check = brain.run(["update", "--check", "--json"])
        let checkForeign = check.jsonObject()?["foreign"] as? [String] ?? []

        // Then
        #expect(!check.succeeded, "a foreign file is drift — check must exit 1")
        #expect(check.jsonObject()?["drift"] as? Bool == true, "\(check.standardOutput)")
        #expect(checkForeign.contains("innate.hand-planted"), "check must name the foreign note: \(check.standardOutput)")

        let update = brain.run(["update", "--json"])
        let updateForeign = update.jsonObject()?["foreign"] as? [String] ?? []

        #expect(!update.succeeded, "a foreign file is drift — update must exit 1")
        #expect(updateForeign.contains("innate.hand-planted"), "update must report the foreign note: \(update.standardOutput)")
        #expect(try String(contentsOf: stranger, encoding: .utf8) == content, "a warned update must not touch the file")

        // When — --override makes the space exactly the shipped set.
        let overridden = brain.run(["update", "--override", "--json"])
        let removed = overridden.jsonObject()?["removed"] as? [String] ?? []

        // Then
        #expect(overridden.succeeded, "\(overridden.standardError)")
        #expect(removed.contains("innate.hand-planted"), "--override must report the removal: \(overridden.standardOutput)")
        #expect(!FileManager.default.fileExists(atPath: stranger.path), "--override must remove a foreign note")
    }
    
    // innate/ is an ordinary branch now, so a note addressed under it puts a
    // directory at its top level. Removing entries rather than notes would take
    // the whole subtree with it — a directory is not something a release ships.
    @Test("--override removes foreign notes one by one, never a directory whole")
    func overrideNeverDeletesASubtreeWhole() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-subtree")
        let nested = brain.file("cortex/innate/docs/setup.md")
        
        try FileManager.default.createDirectory(
            at: nested.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        ---
        id: innate.docs.setup
        title: setup
        priority: lazy
        tags: [innate]
        summary: authored under the innate branch
        ---
        
        ## Note
        mine, not the release's.
        """.write(to: nested, atomically: true, encoding: .utf8)
        
        let sibling = brain.file("cortex/innate/docs/keep.md")
        
        try """
        ---
        id: innate.docs.keep
        title: keep
        priority: lazy
        tags: [innate]
        summary: also mine
        ---
        
        ## Note
        also mine.
        """.write(to: sibling, atomically: true, encoding: .utf8)
        
        // When
        let overridden = brain.run(["update", "--override", "--json"])
        let removed = overridden.jsonObject()?["removed"] as? [String] ?? []
        
        // Then — both are foreign, so both go, but as two notes named by id.
        #expect(overridden.succeeded, "\(overridden.standardError)")
        #expect(Set(removed).isSuperset(of: ["innate.docs.setup", "innate.docs.keep"]),
            "--override must name every removed note: \(overridden.standardOutput)")
        #expect(!removed.contains("docs"), "a directory is not a note and must never be reported")
    }

    @Test("update touches seed ids only — an authored note is never in its scope")
    func updateLeavesAuthoredNotesAlone() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-scope")
        let authored = brain.noteURL(id: "tech.di-container")
        let before = try String(contentsOf: authored, encoding: .utf8)

        // When
        let result = brain.run(["update"])

        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(try String(contentsOf: authored, encoding: .utf8) == before)
    }

    @Test("a locked seed refuses an ops mutation")
    func seededNoteRefusesOpsMutation() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-innate-locked")
        let seed = try firstSeed()

        // When
        let result = brain.applyOps("""
            {"ops":[{"op":"set_frontmatter","id":"\(seed.id)","fields":{"summary":"hijacked"}}],\
            "rationale":"test"}
            """)

        // Then
        #expect(!result.succeeded || result.jsonObject()?["status"] as? String == "rejected",
            "locked seed accepted an ops mutation: \(result.standardOutput)")
    }

    @Test("locked is a bot-mutation gate, not ownership — update restates the seed either way")
    func updateRestatesSeedRegardlessOfLocked() throws {
        // Given — force: a bare fixture home has no innate/ yet, and this test is about
        // content ownership, not the presence contract.
        _ = Seeding.plant(mode: .missingOnly, force: true)

        let seed = try firstSeed()
        let file = Paths.file(forId: seed.id)
        let forked = seed.markdown.replacingOccurrences(of: "locked: true", with: "locked: false")
            + "\n## Local fork\nauthored by a person\n"

        try forked.write(to: file, atomically: true, encoding: .utf8)

        // When
        let result = Seeding.plant(mode: .overwrite)

        // Then
        #expect(result.refreshed.contains(seed.id),
            "a seed id is always the shipped copy, locked or not — got \(result)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)
    }

    // MARK: - Private
    private func seedFile(_ id: String) -> URL {
        source.file("document/innate/\(id).md")
    }

    private func firstSeed() throws -> Innate.Seed {
        guard let seed = Innate.seeds.first else { throw TestFailure("no innate seeds embedded") }

        return seed
    }
}
