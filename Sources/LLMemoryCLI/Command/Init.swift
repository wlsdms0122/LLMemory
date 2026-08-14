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
            case homePath = "home", indexed, changed, errors, base
            case planted, refreshed, unchanged
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
        // Whether the base knowledge was attempted at all — three empty lists
        // read the same whether nothing needed doing or nothing was tried.
        let base: Bool
        let planted, refreshed, unchanged: [String]
        
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
            plants the base knowledge (document/cortex/**/*.md) as `locked: true`
            notes at the addresses that tree gives them. A base id always carries
            the shipped copy, so an existing one is restated. `--no-base` skips
            them — a brain born with nothing at all.

            EXAMPLES
                llmemory init --home brain
                llmemory init --no-base --home brain
            """
    )

    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat

    @Flag(name: .long, inversion: .prefixedNo, help: "Plant the shipped base knowledge.")
    var base = true

    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let result = try Brain(home: global.home).index.initialize(base: base)
        let output = InitOutput(
            alreadyInitialized: result.alreadyInitialized,
            homePath: result.homePath,
            dataExisted: result.dataExisted,
            cortexExisted: result.cortexExisted,
            dbExisted: result.dbExisted,
            indexed: result.indexed,
            changed: result.changed,
            errors: result.errors,
            base: result.seeding != nil,
            planted: result.seeding?.planted ?? [],
            refreshed: result.seeding?.refreshed ?? [],
            unchanged: result.seeding?.unchanged ?? []
        )
        
        render(output, json: format.json) { output in
            [
                .text(output.alreadyInitialized
                    ? "already initialized at \(output.homePath) — preserved existing files "
                        + "(data=\(output.dataExisted), cortex=\(output.cortexExisted), db=\(output.dbExisted))"
                    : "initialized at \(output.homePath)"),
                .text("indexed \(output.indexed) notes (changed=\(output.changed), errors=\(output.errors.count))"),
                .text(!output.base
                    ? "base knowledge: skipped (--no-base)"
                    : output.planted.isEmpty && output.refreshed.isEmpty
                        ? "base knowledge: already current"
                        : "base knowledge — planted: \(output.planted.isEmpty ? "-" : output.planted.joined(separator: ", "))"
                            + ", refreshed: \(output.refreshed.isEmpty ? "-" : output.refreshed.joined(separator: ", "))")
            ]
        }
        
        for error in result.errors {
            FileHandle.standardError.write("  ERROR \(error)\n".data(using: .utf8)!)
        }
        
        if !result.errors.isEmpty { throw ExitCode(1) }
    }
    
    // MARK: - Private
}
