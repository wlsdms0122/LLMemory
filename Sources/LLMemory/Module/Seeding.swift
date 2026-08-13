//
//  Seeding.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum Seeding {
    public enum Mode: Sendable {
        case missingOnly
        case overwrite
    }

    public struct Result: Sendable {
        // MARK: - Property
        public var planted: [String] = []
        public var refreshed: [String] = []
        public var unchanged: [String] = []
        // Seeds not planted because the brain opted out of the innate space
        // (cortex/.innate/ deleted, or init --bare). `--override` re-adopts.
        public var skipped: [String] = []
        // Files inside cortex/.innate/ the release does not ship. Humans own their
        // content, so plant reports them and leaves them alone.
        public var foreign: [String] = []
        public var errors: [String] = []

        // MARK: - Initializer
        // MARK: - Public
        public var wouldChange: Bool { !planted.isEmpty || !refreshed.isEmpty }
        // Any way the innate space differs from the shipped copy — what plant would
        // rewrite plus what it would never touch (foreign files).
        public var drift: Bool { wouldChange || !foreign.isEmpty }

        // MARK: - Private
    }

    // MARK: - Initializer
    // MARK: - Public
    // The cortex/innate/ directory is the contract: while it exists the space is
    // system-managed and seeds inside it always carry the shipped copy. A human opts out
    // by deleting the directory itself — then plant skips until `--override` re-adopts.
    // Nothing outside cortex/innate/ is ever consulted or touched.
    public static func plant(mode: Mode, force: Bool = false, dryRun: Bool = false) -> Result {
        var result = Result()
        let fileManager = FileManager.default
        let present = fileManager.fileExists(atPath: Paths.innate.path)

        guard force || present else {
            result.skipped = Innate.seeds.map { seed in seed.id }
            return result
        }

        for seed in Innate.seeds {
            let canonical = Paths.file(forId: seed.id)
            let exists = fileManager.fileExists(atPath: canonical.path)
            let current = exists ? try? String(contentsOf: canonical, encoding: .utf8) : nil

            if exists && mode == .missingOnly {
                result.unchanged.append(seed.id)
                continue
            }

            if exists, current == seed.markdown {
                result.unchanged.append(seed.id)
                continue
            }

            do {
                if !dryRun {
                    try fileManager.createDirectory(
                        at: canonical.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try seed.markdown.write(to: canonical, atomically: true, encoding: .utf8)
                }

                if exists {
                    result.refreshed.append(seed.id)
                } else {
                    result.planted.append(seed.id)
                }
            } catch {
                result.errors.append("\(seed.id): \(error)")
            }
        }

        result.foreign = foreignNotes()

        return result
    }

    // MARK: - Private
    // `update --override` makes cortex/innate/ exactly the shipped set — notes the
    // release does not ship are removed. Returns the ids that were deleted.
    //
    // Note by note, never entry by entry. innate/ is an ordinary branch of the
    // address space now, so `innate.docs.setup` puts a *directory* named docs at
    // its top level; removing that entry would take the whole subtree with it,
    // and a directory is not a thing the release ships or does not ship.
    public static func removeForeign() -> [String] {
        var removed: [String] = []

        for id in foreignNotes() {
            if (try? FileManager.default.removeItem(at: Paths.file(forId: id))) != nil {
                removed.append(id)
            }
        }

        return removed
    }

    private static func foreignNotes() -> [String] {
        let shipped = Set(Innate.seeds.map { seed in seed.id })

        return Paths.scanNotes()
            .compactMap { file in Paths.id(ofFile: file) }
            .filter { id in id.hasPrefix(Paths.innateBranch + ".") && !shipped.contains(id) }
            .sorted()
    }

}
