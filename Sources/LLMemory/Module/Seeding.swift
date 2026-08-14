//
//  Seeding.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

// The knowledge a release ships as seeds. They are planted at the addresses
// document/cortex/ gives them — anywhere in the space, in any shape — so there
// is no system-managed directory and nothing here knows a privileged branch name.
//
// A seed id carries the shipped copy, and `seed: true` in the frontmatter is how
// a note says it holds one. That mark is the whole reason a reserved directory
// is not needed: without it, "a file is already here" cannot distinguish the
// copy an earlier release planted from a note a person wrote at the same
// address, and a release that later adds an id someone is already using would
// overwrite their work with a one-line report.
//
// So the two are separated, and only the first is ours to rewrite:
//
//   marked   → restate it, silently if identical, named under `refreshed` if not
//   unmarked → a conflict. Nothing is planted at all until it is resolved, by
//              moving the note aside or by saying `--force`.
//
// And the mark is what makes this a reconciliation rather than a one-way copy.
// Walking only the ids a release ships would never notice the ones it stopped
// shipping: a note left claiming to be a release's copy that no release plants,
// which nothing updates and nothing can find. Those are retired — moved to
// cortex/.trash/, because a release may unown its own copy but is in no position
// to destroy what a person kept.
//
// Intent is never read out of the filesystem otherwise — a missing file used to
// mean "opted out" and an edited one "leave me alone", and reading both out of
// one directory is what made this surface need a --check flag to explain itself.
// A brain that does not want the seeds says so per invocation, and a local fork
// of a seeded note lives at its own id.
public enum Seeding {
    public struct Result: Sendable {
        // MARK: - Property
        public var planted: [String] = []
        public var refreshed: [String] = []
        public var unchanged: [String] = []
        // Ids that still claim a seeded copy this release does not ship — moved
        // to cortex/.trash/.
        public var retired: [String] = []
        // Seed ids whose address is held by a note that does not claim to hold a
        // seeded copy. Non-empty means nothing was written.
        public var conflicts: [String] = []
        public var errors: [String] = []

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Initializer
    // MARK: - Public
    // `seeded` is what the brain records as holding a seeded copy — the catalog
    // narrows the search, and the file decides, because the row is only as fresh
    // as the last index and this ends in a file being moved. A mark planted by
    // hand since then is retired one cycle later, when the index has caught up.
    public static func plant(force: Bool = false, seeded: [String] = [], now: Int = 0) -> Result {
        var result = Result()

        // Surveyed before anything is written, so a conflict on the last seed
        // does not leave the ones before it already replaced. All or nothing is
        // also what makes the report actionable: the ids listed are exactly the
        // ids to deal with, not whatever was left after a partial run.
        if !force {
            result.conflicts = Seed.notes
                .filter { seed in
                    if case .foreign = claimant(of: seed) { return true }

                    return false
                }
                .map { seed in seed.id }

            if !result.conflicts.isEmpty { return result }
        }

        for seed in Seed.notes {
            let canonical = Paths.file(forId: seed.id)
            let exists = FileManager.default.fileExists(atPath: canonical.path)

            switch claimant(of: seed) {
            case .identical:
                result.unchanged.append(seed.id)
                continue

            case .unreadable(let reason):
                // A file that is there but cannot be read is not a file that
                // differs — sending it down the overwrite path is where whatever
                // it held would stop existing.
                result.errors.append("\(seed.id): present but unreadable, left alone (\(reason))")
                continue

            case .absent, .ours, .foreign:
                break
            }

            do {
                try FileManager.default.createDirectory(
                    at: canonical.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try seed.markdown.write(to: canonical, atomically: true, encoding: .utf8)

                // Reported separately because overwriting is the one outcome a
                // human could be surprised by — a run that rewrites an edit says
                // which id it rewrote.
                if exists {
                    result.refreshed.append(seed.id)
                } else {
                    result.planted.append(seed.id)
                }
            } catch {
                result.errors.append("\(seed.id): \(error)")
            }
        }

        let shipped = Set(Seed.notes.map { note in note.id })

        for id in seeded.sorted() where !shipped.contains(id) {
            let file = Paths.file(forId: id)

            // Confirmed against the file, not taken from the row: what is there
            // now may no longer be the copy the catalog remembers.
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                let (fields, _) = try? Frontmatter.parse(text), fields.seed
            else {
                continue
            }

            do {
                try Trash.file(file, reason: "no longer shipped by this release", now: now)
                result.retired.append(id)
            } catch {
                result.errors.append("\(id): \(error)")
            }
        }

        return result
    }

    // MARK: - Private
    private enum Claimant {
        case absent
        case identical
        // Marked `seed: true` — a copy of some release's, ours to restate.
        case ours
        // Someone else's note sitting at an address this release wants.
        case foreign
        case unreadable(String)
    }

    private static func claimant(of seed: Seed.Note) -> Claimant {
        let canonical = Paths.file(forId: seed.id)

        guard FileManager.default.fileExists(atPath: canonical.path) else { return .absent }

        let text: String
        do {
            text = try String(contentsOf: canonical, encoding: .utf8)
        } catch {
            return .unreadable("\(error)")
        }

        if text == seed.markdown { return .identical }

        // An unparseable file cannot show the mark, and a file that cannot show
        // the mark is not one this release may overwrite.
        guard let (fields, _) = try? Frontmatter.parse(text) else { return .foreign }

        return fields.seed ? .ours : .foreign
    }
}
