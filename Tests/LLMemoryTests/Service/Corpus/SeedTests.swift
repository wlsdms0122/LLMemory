//
//  SeedTests.swift
//  LLMemoryTests
//
//  Created by JSilver on 8/8/26.
//

import Testing
import Foundation
@testable import LLMemory

// The notes a release ships as seeds. One sentence carries the whole contract —
// a seed id always holds the shipped copy — so these tests are mostly about what
// is *not* here any more: no privileged directory, no state read as intent, no
// second command to explain the first.
@Suite("Seed Tests")
struct SeedTests {
    // MARK: - Property
    private let source = PackageSource()
    private let home: MemoryHome

    private let frontmatter = Frontmatter()

    private var seeding: Seeding { Seeding(layout: home.layout) }

    // MARK: - Initializer
    init() throws {
        home = try MemoryHome()
    }

    // MARK: - Test
    @Test("the embedded seeds are byte-identical to the documents they were generated from")
    func embeddedSeedsMatchDocumentFiles() throws {
        // Given
        #expect(!Seed.notes.isEmpty, "no seed notes embedded")

        for seed in Seed.notes {
            // When
            let onDisk = try String(contentsOf: seedFile(seed.id), encoding: .utf8)

            // Then
            #expect(onDisk == seed.markdown,
                "\(seedFile(seed.id).path) and Seed.swift diverged — run tool/set-up.sh")
        }
    }

    // Every other test here iterates Seed.notes, so a document added without
    // rerunning tool/set-up.sh is a document nothing looks at. This walks the
    // other way — from the tree.
    //
    // The comparison is by *path*, through Path, rather than by an id this test
    // derives for itself: re-spelling the generator's split-on-dots here would
    // put two copies of one rule on either side of the assertion, and two copies
    // that are wrong together still agree.
    @Test("the embedded set is exactly the document tree — nothing missing, nothing extra")
    func embeddedSeedsAreExactlyTheDocumentTree() throws {
        // Given
        let root = source.file("document/cortex")
        var onDisk = Set<String>()

        guard let walk = FileManager.default.enumerator(atPath: root.path) else {
            throw TestFailure("document/cortex is not readable at \(root.path)")
        }

        for case let relative as String in walk where relative.hasSuffix(".md") {
            onDisk.insert(root.appendingPathComponent(relative).standardized.path)
        }

        // When — where the brain would put each embedded seed, by its own mapping.
        let embedded = Set(Seed.notes.map { seed in seedFile(seed.id).standardized.path })

        // Then
        #expect(!onDisk.isEmpty, "no documents found under \(root.path)")
        #expect(onDisk.subtracting(embedded).isEmpty,
            "documents no embedded seed addresses — run tool/set-up.sh: \(onDisk.subtracting(embedded).sorted())")
        #expect(embedded.subtracting(onDisk).isEmpty,
            "embedded seeds whose address holds no document: \(embedded.subtracting(onDisk).sorted())")
    }

    @Test("every seed declares locked: true, so ops cannot rewrite the shipped copy")
    func everySeedIsLocked() throws {
        for seed in Seed.notes {
            // When
            let onDisk = try String(contentsOf: seedFile(seed.id), encoding: .utf8)

            // Then
            #expect(onDisk.contains("\nlocked: true\n"), "\(seed.id) must declare locked: true")
        }
    }

    @Test("a seed is addressed by where it is planted, and declares no id of its own")
    func seedDeclaresNoId() throws {
        for seed in Seed.notes {
            // When
            _ = try frontmatter.parse(seed.markdown)

            // Then
            #expect(!seed.markdown.contains("\nid:"),
                "\(seed.id): the markdown still declares an id line")
        }
    }

    @Test("init plants the seed notes as notes that can actually be retrieved")
    func initPlantsSeedsAsRetrievableNotes() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-init")

        for seed in Seed.notes {
            // When
            let planted = brain.file(home.layout.relativeFile(forId: seed.id))
            let result = brain.run(["query", "get", seed.id, "--json"])

            // Then
            #expect(FileManager.default.fileExists(atPath: planted.path), "\(seed.id) not planted")
            #expect(result.succeeded, "planted note not retrievable: \(result.standardError)")
        }
    }

    @Test("a fresh brain holds exactly the shipped set and nothing else")
    func freshBrainHoldsOnlyTheSeedNotes() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-tree", seeded: false)

        // When
        let result = brain.run(["query", "tree", "--json"])
        let rows = result.jsonArrayOfArrays() ?? []
        let prefixes = Set(rows.compactMap { row in row.first as? String })

        // Then
        #expect(prefixes == Set(Seed.notes.compactMap { seed in NoteAddress.branch(of: seed.id, depth: 1) }),
            "fresh brain tree: \(prefixes.sorted())")
    }

    // The shipped copy wins at a seed id, always — that is the entire contract,
    // and it is why nothing needs to ask whether an edit was deliberate.
    @Test("an edited seed note is restated, and the run says which id it rewrote")
    func updateRestatesAnEditedSeedNote() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-edit")
        let seed = try firstSeed()
        let file = brain.file(home.layout.relativeFile(forId: seed.id))

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
    // filesystem carries no intent, so a brain that does not want the seed
    // knowledge says so on the command line instead.
    @Test("a deleted seed note comes back on the next update")
    func updateReplantsADeletedSeedNote() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-delete")
        let seed = try firstSeed()
        let file = brain.file(home.layout.relativeFile(forId: seed.id))

        try FileManager.default.removeItem(at: file)

        // When
        let result = brain.run(["update", "--json"])

        // Then
        let planted = result.jsonObject()?["planted"] as? [String] ?? []

        #expect(result.succeeded, "\(result.standardError)")
        #expect(planted.contains(seed.id), "update must replant: \(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)
    }

    // The markdown is the source and the DB is its reflection, so a frontmatter
    // field llmemory itself branches on belongs in the schema — otherwise the
    // fact exists in the file and nowhere a query can reach it.
    @Test("the seed mark is projected onto the note row")
    func theSeedMarkIsProjected() throws {
        // Given
        _ = seeding.plant(force: false, seeded: [], now: home.now, db: try home.bootstrapScope())

        #expect(home.createNote(id: "tech.mine", content: "## A\nmine\n").status == "ok")

        for seed in Seed.notes {
            try home.reindexFile(at: home.layout.file(forId: seed.id))
        }

        // When
        let marked = try home.read { database in
            try String.fetchAll(database, sql: "SELECT id FROM notes WHERE seed = 1 ORDER BY id")
        }
        let unmarked = try home.read { database in
            try String.fetchAll(database, sql: "SELECT id FROM notes WHERE seed = 0 ORDER BY id")
        }

        // Then
        #expect(marked == Seed.notes.map(\.id).sorted(), "\(marked)")
        #expect(unmarked == ["tech.mine"], "an authored note must claim nothing: \(unmarked)")
    }

    @Test("every shipped document declares seed: true, or nothing could tell it from an authored note")
    func everySeedDeclaresSeed() throws {
        for seed in Seed.notes {
            // When
            let (fields, _) = try frontmatter.parse(seed.markdown)

            // Then
            #expect(fields.seed, "\(seed.id) must declare seed: true")
        }
    }

    // The address is shared with authored notes now, so a release that adds an
    // id someone already uses must not be able to take it. Without the mark this
    // note is indistinguishable from a seeded copy that was edited.
    @Test("a note at a seed address that does not claim to be seed notes stops the planting")
    func anUnmarkedNoteAtASeedAddressIsAConflict() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-conflict", seeded: false, seed: false)
        let seed = try firstSeed()
        let file = brain.file(home.layout.relativeFile(forId: seed.id))
        let mine = """
        ---
        title: mine
        priority: lazy
        tags: [flow]
        summary: I got here first
        ---

        ## Note
        authored, not shipped.
        """

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try mine.write(to: file, atomically: true, encoding: .utf8)

        // When
        let result = brain.run(["update", "--json"])

        // Then — named, refused, and the note is still theirs.
        let conflicts = result.jsonObject()?["conflicts"] as? [String] ?? []

        #expect(!result.succeeded, "a conflict must exit 1")
        #expect(conflicts == [seed.id], "\(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == mine, "the note was overwritten")

        // When — --force is the only way through, and it says so by being asked for.
        let forced = brain.run(["update", "--force", "--json"])

        #expect(forced.succeeded, "\(forced.standardError)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)

        // Then — the address was taken, not the note destroyed. Overruling a
        // person stays undoable, and the run says whose address it took.
        let replaced = forced.jsonObject()?["replaced"] as? [String] ?? []
        let trashed = brain.file("cortex/.trash/\(seed.id.replacingOccurrences(of: ".", with: "/")).md")

        #expect(replaced == [seed.id], "\(forced.standardOutput)")
        #expect(FileManager.default.fileExists(atPath: trashed.path),
            "--force erased an authored note instead of trashing it")
        #expect(try String(contentsOf: trashed, encoding: .utf8).contains("I got here first"))
    }

    // All or nothing: the ids reported are the ids to deal with, not whatever
    // survived a partial run.
    @Test("a conflict plants nothing at all, not even the seeds that would have been fine")
    func aConflictLeavesEverySeedUnplanted() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-allornothing", seeded: false, seed: false)
        let seed = try firstSeed()
        let file = brain.file(home.layout.relativeFile(forId: seed.id))

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        ---
        title: mine
        priority: lazy
        tags: [flow]
        summary: I got here first
        ---

        ## Note
        authored.
        """.write(to: file, atomically: true, encoding: .utf8)

        // When
        let result = brain.run(["update", "--json"])

        // Then
        let planted = result.jsonObject()?["planted"] as? [String] ?? []
        let refreshed = result.jsonObject()?["refreshed"] as? [String] ?? []

        #expect(planted.isEmpty && refreshed.isEmpty, "\(result.standardOutput)")

        for other in Seed.notes where other.id != seed.id {
            #expect(!FileManager.default.fileExists(
                atPath: brain.file(home.layout.relativeFile(forId: other.id)).path
            ), "\(other.id) was planted while another seed was in conflict")
        }
    }

    // Walking only the ids a release ships can never find the ones it stopped
    // shipping. Those notes claim a provenance nothing backs, and nothing else
    // would ever look at them again.
    @Test("an id the release no longer ships is retired to the trash and reported")
    func aRetiredSeedIsTrashedAndReported() throws {
        // Given — a note that claims to be a seeded copy at an id nothing ships.
        let brain = try CLIBrain(prefix: "llmemory-seed-retire")
        let retired = brain.file(home.layout.relativeFile(forId: "innate.gone"))

        try FileManager.default.createDirectory(
            at: retired.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        ---
        title: gone
        priority: lazy
        tags: [flow]
        seed: true
        locked: true
        summary: shipped by a release that no longer ships it
        ---

        ## Note
        left behind.
        """.write(to: retired, atomically: true, encoding: .utf8)

        #expect(brain.applyOps("""
            {"ops":[{"op":"create_note","id":"tech.cites-gone","title":"t","tags":["flow"],\
            "summary":"s","content":"## A\\ncites `innate.gone`.\\n"}],"rationale":"test"}
            """).succeeded)

        // The catalog has to know it before update can look for it.
        #expect(brain.run(["index", "build"]).succeeded)

        // When
        let result = brain.run(["update", "--json"])

        // Then
        let reported = result.jsonObject()?["retired"] as? [String] ?? []

        #expect(result.succeeded, "\(result.standardError)")
        #expect(reported == ["innate.gone"], "\(result.standardOutput)")
        #expect(!FileManager.default.fileExists(atPath: retired.path))
        #expect(FileManager.default.fileExists(
            atPath: brain.file("cortex/.trash/innate/gone.md").path
        ), "a retired note is moved, not erased")

        // A note leaving the corpus is a note somebody may have cited. Retirement
        // goes through the same removal as a deletion, so the citers are flagged
        // the same way rather than discovering it as a dangling reference.
        let flagged = try brain.rows("SELECT note_id FROM ripple_flags ORDER BY note_id")

        #expect(flagged.contains("tech.cites-gone"), "the citer was not flagged: \(flagged)")
    }

    // The row is only as fresh as the last index, and this ends in a file being
    // moved — so the catalog says where to look and the file says what to do.
    @Test("a note the catalog calls seeded is left alone once the file no longer claims it")
    func retirementIsConfirmedAgainstTheFile() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-retire-claim")
        let file = brain.file(home.layout.relativeFile(forId: "innate.gone"))

        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        ---
        title: gone
        priority: lazy
        tags: [flow]
        seed: true
        summary: seeded for now
        ---

        ## Note
        left behind.
        """.write(to: file, atomically: true, encoding: .utf8)

        #expect(brain.run(["index", "build"]).succeeded)

        // When — the mark is dropped after the catalog recorded it: the note is
        // claimed by a person now.
        let mine = """
        ---
        title: gone
        priority: lazy
        tags: [flow]
        summary: mine now
        ---

        ## Note
        mine.
        """

        try mine.write(to: file, atomically: true, encoding: .utf8)

        let result = brain.run(["update", "--json"])

        // Then
        let reported = result.jsonObject()?["retired"] as? [String] ?? []

        #expect(result.succeeded, "\(result.standardError)")
        #expect(reported.isEmpty, "the file no longer claims to be seeded: \(result.standardOutput)")
        #expect(try String(contentsOf: file, encoding: .utf8) == mine)
    }

    @Test("--no-seed leaves the seed notes out — on init and on update alike")
    func noSeedSkipsPlanting() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-none", seeded: false, seed: false)
        let seed = try firstSeed()
        let file = brain.file(home.layout.relativeFile(forId: seed.id))

        #expect(!FileManager.default.fileExists(atPath: file.path), "--no-seed must not plant")

        // When
        let result = brain.run(["update", "--no-seed", "--json"])

        // Then
        #expect(result.succeeded, "\(result.standardError)")
        #expect(!FileManager.default.fileExists(atPath: file.path), "--no-seed must not plant on update")

        // When — and the choice is per invocation, not a setting the brain keeps.
        let again = brain.run(["update", "--json"])

        #expect(again.succeeded, "\(again.standardError)")
        #expect(FileManager.default.fileExists(atPath: file.path),
            "a plain update must plant: \(again.standardOutput)")
    }

    // There is no system-managed directory any more, so a seeded note's neighbours
    // are ordinary notes — including the ones addressed underneath it.
    @Test("update touches seed ids only — authored notes beside and beneath them are left alone")
    func updateLeavesAuthoredNotesAlone() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-db")
        let seed = try firstSeed()
        let authored = brain.noteURL(id: "tech.di-container")
        let before = try String(contentsOf: authored, encoding: .utf8)
        let beneath = brain.file(home.layout.relativeFile(forId: "\(seed.id).mine"))

        try FileManager.default.createDirectory(
            at: beneath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let mine = """
        ---
        title: mine
        priority: lazy
        tags: [flow]
        summary: authored under a seeded note's address
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
            "a note under a seeded note's address is not the release's to touch")
    }

    // The mark decides who may overwrite whom, so a note that could set it on
    // itself could arrange to be replaced by the next release.
    @Test("ops cannot author the seed mark")
    func opsCannotSetTheSeedMark() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-reserved")

        #expect(brain.applyOps("""
            {"ops":[{"op":"create_note","id":"tech.mine","title":"t","tags":["flow"],\
            "summary":"s","content":"## A\\nbody"}],"rationale":"test"}
            """).succeeded)

        // When
        let result = brain.applyOps("""
            {"ops":[{"op":"set_frontmatter","id":"tech.mine","fields":{"seed":true}}],\
            "rationale":"test"}
            """)

        // Then
        #expect(!result.succeeded || result.jsonObject()?["status"] as? String == "rejected",
            "a note granted itself the seed mark: \(result.standardOutput)")
        #expect(!(try String(contentsOf: brain.noteURL(id: "tech.mine"), encoding: .utf8))
            .contains("seed:"), "the mark reached the file")
    }

    @Test("a locked seed note refuses an ops mutation")
    func seedNoteRefusesOpsMutation() throws {
        // Given
        let brain = try CLIBrain(prefix: "llmemory-seed-locked")
        let seed = try firstSeed()

        // When
        let result = brain.applyOps("""
            {"ops":[{"op":"set_frontmatter","id":"\(seed.id)","fields":{"summary":"hijacked"}}],\
            "rationale":"test"}
            """)

        // Then
        #expect(!result.succeeded || result.jsonObject()?["status"] as? String == "rejected",
            "locked seed note accepted an ops mutation: \(result.standardOutput)")
    }

    @Test("locked is a bot-mutation gate, not ownership — planting restates the note either way")
    func plantRestatesSeedRegardlessOfLocked() throws {
        // Given
        _ = seeding.plant(force: false, seeded: [], now: home.now, db: try home.bootstrapScope())

        let seed = try firstSeed()
        let file = home.layout.file(forId: seed.id)
        let forked = seed.markdown.replacingOccurrences(of: "locked: true", with: "locked: false")
            + "\n## Local fork\nauthored by a person\n"

        try forked.write(to: file, atomically: true, encoding: .utf8)

        // When
        let result = seeding.plant(force: false, seeded: [], now: home.now, db: try home.bootstrapScope())

        // Then
        #expect(result.refreshed.contains(seed.id),
            "a seed id is always the shipped copy, locked or not — got \(result)")
        #expect(try String(contentsOf: file, encoding: .utf8) == seed.markdown)
    }

    // MARK: - Private
    // document/ holds the shipped subtree of a cortex, so a seed's document sits
    // at exactly the brain-relative path its id spells. Going through Path rather
    // than repeating the mapping here makes that sameness the thing under test.
    private func seedFile(_ id: String) -> URL {
        source.file("document/\(home.layout.relativeFile(forId: id))")
    }

    private func firstSeed() throws -> Seed.Note {
        guard let seed = Seed.notes.first else { throw TestFailure("no seed notes embedded") }

        return seed
    }
}
