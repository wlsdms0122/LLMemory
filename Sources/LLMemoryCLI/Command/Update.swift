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
        // Whether the base knowledge was attempted at all — three empty lists
        // read the same whether nothing needed doing or nothing was tried.
        let base: Bool
        let planted, refreshed, unchanged: [String]
        let indexed, changed: Int
        let errors: [String]

        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }

    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Carry an existing brain forward to this binary — schema, manual, base knowledge.",
        discussion: """
            Applies any pending schema migrations, rewrites <home>/README.md from
            the embedded guide, restates the base knowledge, and reindexes.

            A base id always carries the shipped copy — an edited one is rewritten
            and reported under `refreshed`, so a local fork belongs at its own id
            rather than on top of a base note. `--no-base` leaves the base notes
            untouched; it is a per-invocation choice, not a setting the brain
            remembers.

            Authored notes are never in scope. Nothing is ever deleted.

            EXAMPLES
                llmemory update --home brain
                llmemory update --no-base --json --home brain
            """
    )

    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat

    @Flag(name: .long, inversion: .prefixedNo, help: "Restate the shipped base knowledge.")
    var base = true

    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let result = try Brain(home: global.home).index.update(base: base)
        let output = UpdateOutput(
            home: result.homePath,
            base: result.seeding != nil,
            planted: result.seeding?.planted ?? [],
            refreshed: result.seeding?.refreshed ?? [],
            unchanged: result.seeding?.unchanged ?? [],
            indexed: result.indexed,
            changed: result.changed,
            errors: result.errors
        )

        render(output, json: format.json) { output in
            [
                .keyValue([
                    ("home", output.home),
                    ("base", output.base ? "restated" : "skipped (--no-base)"),
                    ("planted", output.planted.isEmpty ? "-" : output.planted.joined(separator: ", ")),
                    ("refreshed", output.refreshed.isEmpty ? "-" : output.refreshed.joined(separator: ", ")),
                    ("unchanged", output.unchanged.isEmpty ? "-" : output.unchanged.joined(separator: ", "))
                ]),
                .text("indexed \(output.indexed) notes (changed=\(output.changed), errors=\(output.errors.count))")
            ]
        }

        for error in result.errors {
            FileHandle.standardError.write("  ERROR \(error)\n".data(using: .utf8)!)
        }

        if !result.errors.isEmpty { throw ExitCode(1) }
    }

    // MARK: - Private
}
