//
//  Init.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct InitCommand: ParsableCommand {
    struct InitOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case homePath = "home", indexed, changed, errors
            case seedsPlanted = "seeds_planted"
            case alreadyInitialized = "already_initialized"
            case dataExisted = "data_existed"
            case cortexExisted = "cortex_existed"
            case dbExisted = "db_existed"
        }
        
        // MARK: - Property
        let alreadyInitialized: Bool
        let homePath: String
        let dataExisted, cortexExisted, dbExisted: Bool
        let indexed: Int
        let changed: Int
        let errors: [String]
        let seedsPlanted: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a brain home (data/, cortex/, memory.db).",
        discussion: """
            Idempotent — existing state is preserved and only missing pieces are
            created. A fresh brain starts with no notes and no tag vocabulary —
            everything grows through ops.

            Also writes <home>/README.md from the embedded agent guide
            (document/GUIDE.md) — a derived copy, refreshed on every init — and
            plants the innate notes (document/innate/**/*.md) as `locked: true`
            notes under cortex/innate/. Existing seed files are left alone here;
            use `llmemory update` to restate them from the binary. `--bare` skips
            the innate space entirely — a brain born with nothing at all.

            EXAMPLES
                llmemory init --home brain
                llmemory init --bare --home brain
            """
    )

    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat

    @Flag(name: .long, help: "Do not plant the innate notes — start completely empty.")
    var bare = false

    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let result = try Brain(home: global.home).index.initialize(bare: bare)
        let output = InitOutput(
            alreadyInitialized: result.alreadyInitialized,
            homePath: result.homePath,
            dataExisted: result.dataExisted,
            cortexExisted: result.cortexExisted,
            dbExisted: result.dbExisted,
            indexed: result.indexed,
            changed: result.changed,
            errors: result.errors,
            seedsPlanted: result.seeding.planted
        )
        
        render(output, json: format.json) { output in
            [
                .text(output.alreadyInitialized
                    ? "already initialized at \(output.homePath) — preserved existing files "
                        + "(data=\(output.dataExisted), cortex=\(output.cortexExisted), db=\(output.dbExisted))"
                    : "initialized at \(output.homePath)"),
                .text("indexed \(output.indexed) notes (changed=\(output.changed), errors=\(output.errors.count))"),
                .text(bare
                    ? "innate seeds: skipped (--bare)"
                    : output.seedsPlanted.isEmpty
                        ? "innate seeds: already present"
                        : "innate seeds planted: \(output.seedsPlanted.joined(separator: ", "))")
            ]
        }
        
        for error in result.errors {
            FileHandle.standardError.write("  ERROR \(error)\n".data(using: .utf8)!)
        }
        
        if !result.errors.isEmpty { throw ExitCode(1) }
    }
    
    // MARK: - Private
}
