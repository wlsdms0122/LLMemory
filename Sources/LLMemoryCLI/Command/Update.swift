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
        let planted, refreshed, unchanged, skipped, foreign, removed: [String]
        let blocked: Bool
        let indexed, changed: Int
        let errors: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    struct CheckOutput: Encodable {
        // MARK: - Property
        let home: String
        let planted, refreshed, unchanged, skipped, foreign: [String]
        let drift: Bool
        let errors: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Refresh the shipped innate notes + manual in an existing brain.",
        discussion: """
            Rewrites <home>/README.md from the embedded guide and reindexes. The
            innate space (cortex/.innate/, `locked: true` seed notes) is handled by
            comparison with the shipped copy:

            - matches exactly  → nothing to do.
            - directory absent → opted out; skipped quietly.
            - differs in ANY way (edited content, missing file, a file the
              release does not ship) → update WARNS, leaves the space untouched,
              and exits 1.

            `--override` restates the space to exactly the shipped set: overwrites
            edited seeds, replants missing ones, and removes foreign files. `--check` reports the same classification
            without writing anything (exit 1 on drift).

            Authored notes outside cortex/.innate/ are never in scope.

            EXAMPLES
                llmemory update --home brain
                llmemory update --check --json --home brain
                llmemory update --override --home brain
            """
    )

    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat

    @Flag(name: .long, help: "Restate cortex/.innate/ to exactly the shipped set (removes foreign files).")
    var override = false

    @Flag(name: .long, help: "Report what update would do without writing anything. Exit 1 on drift.")
    var check = false

    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        if check {
            try runCheck()
            return
        }

        let result = try Index.update(home: global.home, override: override)
        let output = UpdateOutput(
            home: result.homePath,
            planted: result.seeding.planted,
            refreshed: result.seeding.refreshed,
            unchanged: result.seeding.unchanged,
            skipped: result.seeding.skipped,
            foreign: result.seeding.foreign,
            removed: result.removed,
            blocked: result.blocked,
            indexed: result.indexed,
            changed: result.changed,
            errors: result.errors
        )

        render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .keyValue([
                    ("home", output.home),
                    ("planted", output.planted.isEmpty ? "-" : output.planted.joined(separator: ", ")),
                    ("refreshed", output.refreshed.isEmpty ? "-" : output.refreshed.joined(separator: ", ")),
                    ("unchanged", output.unchanged.isEmpty ? "-" : output.unchanged.joined(separator: ", ")),
                    ("skipped", output.skipped.isEmpty ? "-" : output.skipped.joined(separator: ", ")),
                    ("foreign", output.foreign.isEmpty ? "-" : output.foreign.joined(separator: ", ")),
                    ("removed", output.removed.isEmpty ? "-" : output.removed.joined(separator: ", "))
                ])
            ]

            if output.blocked {
                blocks.append(.text(
                    "WARNING: innate space differs from the shipped copy — nothing was "
                        + "touched. Rerun with --override to restate it to the release."
                ))
            }

            blocks.append(
                .text("indexed \(output.indexed) notes (changed=\(output.changed), errors=\(output.errors.count))")
            )

            return blocks
        }

        for error in result.errors {
            FileHandle.standardError.write("  ERROR \(error)\n".data(using: .utf8)!)
        }

        if !result.errors.isEmpty || result.blocked { throw ExitCode(1) }
    }

    // MARK: - Private
    private func runCheck() throws {
        let result = Index.checkSeeds(home: global.home, force: override)
        let output = CheckOutput(
            home: global.home,
            planted: result.planted,
            refreshed: result.refreshed,
            unchanged: result.unchanged,
            skipped: result.skipped,
            foreign: result.foreign,
            drift: result.drift,
            errors: result.errors
        )

        render(output, json: format.json) { output in
            [
                .keyValue([
                    ("home", output.home),
                    ("would plant", output.planted.isEmpty ? "-" : output.planted.joined(separator: ", ")),
                    ("would refresh", output.refreshed.isEmpty ? "-" : output.refreshed.joined(separator: ", ")),
                    ("unchanged", output.unchanged.isEmpty ? "-" : output.unchanged.joined(separator: ", ")),
                    ("skipped", output.skipped.isEmpty ? "-" : output.skipped.joined(separator: ", ")),
                    ("foreign", output.foreign.isEmpty ? "-" : output.foreign.joined(separator: ", "))
                ]),
                .text(output.drift
                    ? "innate space differs from the shipped copy"
                    : "innate space matches the shipped copy")
            ]
        }

        for error in result.errors {
            FileHandle.standardError.write("  ERROR \(error)\n".data(using: .utf8)!)
        }

        if !result.errors.isEmpty || result.drift { throw ExitCode(1) }
    }
}
