//
//  Update.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct UpdateCommand: ParsableCommand {
    struct UpdateOutput: Encodable {
        // MARK: - Property
        let home: String
        // Whether the seeds were attempted at all — three empty lists read the
        // same whether nothing needed doing or nothing was tried.
        let seed: Bool
        let planted, refreshed, unchanged, retired, replaced, conflicts: [String]
        let indexed, changed: Int
        let errors: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Carry an existing brain forward to this binary — schema, manual, seed notes.",
        discussion: """
            Applies any pending schema migrations, rewrites <home>/README.md from
            the embedded guide, restates the seed notes, and reindexes.

            A seed id always carries the shipped copy — an edited one is rewritten
            and reported under `refreshed`, so a local fork belongs at its own id
            rather than on top of a seeded note. `--no-seed` leaves them untouched;
            it is a per-invocation choice, not a setting the brain remembers.

            An id this release no longer ships, still held by a note carrying
            `seed: true`, is retired to cortex/.trash/ and reported — a release
            unowns its own copy rather than leaving it to claim a provenance
            nothing backs. Authored notes are never in scope.

            A seeded note is one that carries `seed: true`. If a release adds an id
            an authored note already holds, that is a conflict: NOTHING is
            planted, the ids are listed, and update exits 1. Move the note to
            another id, or rerun with `--force` to replace it.

            EXAMPLES
                llmemory update --home brain
                llmemory update --no-seed --json --home brain
                llmemory update --force --home brain
            """
    )

    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat

    @Flag(name: .long, inversion: .prefixedNo, help: "Restate the shipped seed notes.")
    var seed = true

    @Flag(name: .long, help: "Replace notes holding a seed address even when they do not claim to hold a seeded copy.")
    var force = false

    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let result = try Brain(home: global.home).index.update(seed: seed, force: force)
        let output = UpdateOutput(
            home: result.homePath,
            seed: result.seeding != nil,
            planted: result.seeding?.planted ?? [],
            refreshed: result.seeding?.refreshed ?? [],
            unchanged: result.seeding?.unchanged ?? [],
            retired: result.seeding?.retired ?? [],
            replaced: result.seeding?.replaced ?? [],
            conflicts: result.seeding?.conflicts ?? [],
            indexed: result.indexed,
            changed: result.changed,
            errors: result.errors
        )

        render(output, json: format.json) { output in
            [.keyValue([("home", output.home)])]
                + SeedingSummary.blocks(
                    attempted: output.seed,
                    planted: output.planted,
                    refreshed: output.refreshed,
                    unchanged: output.unchanged,
                    retired: output.retired,
                    replaced: output.replaced,
                    conflicts: output.conflicts
                )
                + [.text(
                    "indexed \(output.indexed) notes "
                        + "(changed=\(output.changed), errors=\(output.errors.count))"
                )]
        }

        for error in result.errors {
            FileHandle.standardError.write("  ERROR \(error)\n".data(using: .utf8)!)
        }

        if !result.errors.isEmpty || !(result.seeding?.conflicts.isEmpty ?? true) { throw ExitCode(1) }
    }

    // MARK: - Private
}
