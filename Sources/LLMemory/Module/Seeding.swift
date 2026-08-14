//
//  Seeding.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

// The base knowledge a release ships. It is planted at the addresses
// document/cortex/ gives it — anywhere in the space, in any shape — so there is
// no system-managed directory and nothing here knows a privileged branch name.
//
// The contract is one sentence: a base id always carries the shipped copy.
// `init` and `update` restate it, and a brain that does not want it says so per
// invocation. Nothing infers intent from the state of the filesystem — a missing
// file used to mean "opted out" and an edited one "leave me alone", and reading
// those two out of the same directory is what made the seeding surface complex
// enough to need a --check flag to explain itself. A local fork of a base note
// lives at its own id.
public enum Seeding {
    public struct Result: Sendable {
        // MARK: - Property
        public var planted: [String] = []
        public var refreshed: [String] = []
        public var unchanged: [String] = []
        public var errors: [String] = []

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Initializer
    // MARK: - Public
    public static func plant() -> Result {
        var result = Result()
        let fileManager = FileManager.default

        for seed in Base.seeds {
            let canonical = Paths.file(forId: seed.id)
            let exists = fileManager.fileExists(atPath: canonical.path)

            if exists, (try? String(contentsOf: canonical, encoding: .utf8)) == seed.markdown {
                result.unchanged.append(seed.id)
                continue
            }

            do {
                try fileManager.createDirectory(
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

        return result
    }

    // MARK: - Private
}
