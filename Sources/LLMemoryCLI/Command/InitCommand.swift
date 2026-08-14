//
//  InitCommand.swift
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
            case homePath = "home", indexed, changed, errors, seed
            case planted, refreshed, unchanged, retired, replaced, conflicts
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
        // Whether the seeds were attempted at all — three empty lists read the
        // same whether nothing needed doing or nothing was tried.
        let seed: Bool
        let planted, refreshed, unchanged, retired, replaced, conflicts: [String]
        
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
            plants the seed notes (document/cortex/**/*.md) as `locked: true`
            notes at the addresses that tree gives them. A seed id always carries
            the shipped copy, so an existing one — a note carrying `seed: true` —
            is restated. An address held by a note that does not claim to hold a
            seeded copy is a conflict: nothing is planted, the ids are listed, and
            init exits 1 unless `--force` is given. `--no-seed` skips them
            entirely — a brain born with nothing at all.
            
            EXAMPLES
                llmemory init --home brain
                llmemory init --no-seed --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Flag(name: .long, inversion: .prefixedNo, help: "Plant the shipped seed notes.")
    var seed = true
    
    @Flag(name: .long, help: "Replace notes holding a seed address even when they do not claim to hold a seeded copy.")
    var force = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let result = try Brain(home: global.home).index.initialize(seed: seed, force: force)
        let output = InitOutput(
            alreadyInitialized: result.alreadyInitialized,
            homePath: result.homePath,
            dataExisted: result.dataExisted,
            cortexExisted: result.cortexExisted,
            dbExisted: result.dbExisted,
            indexed: result.indexed,
            changed: result.changed,
            errors: result.errors,
            seed: result.seeding != nil,
            planted: result.seeding?.planted ?? [],
            refreshed: result.seeding?.refreshed ?? [],
            unchanged: result.seeding?.unchanged ?? [],
            retired: result.seeding?.retired ?? [],
            replaced: result.seeding?.replaced ?? [],
            conflicts: result.seeding?.conflicts ?? []
        )
        
        CommandOutput().render(output, json: format.json) { output in
            [
                .text(output.alreadyInitialized
                    ? "already initialized at \(output.homePath) — preserved existing files "
                        + "(data=\(output.dataExisted), cortex=\(output.cortexExisted), db=\(output.dbExisted))"
                    : "initialized at \(output.homePath)"),
                .text("indexed \(output.indexed) notes (changed=\(output.changed), errors=\(output.errors.count))")
            ] + SeedingSummary().blocks(
                attempted: output.seed,
                planted: output.planted,
                refreshed: output.refreshed,
                unchanged: output.unchanged,
                retired: output.retired,
                replaced: output.replaced,
                conflicts: output.conflicts
            )
        }
        
        for error in result.errors {
            FileHandle.standardError.write("  ERROR \(error)\n".data(using: .utf8)!)
        }
        
        if !result.errors.isEmpty || !(result.seeding?.conflicts.isEmpty ?? true) { throw ExitCode(1) }
    }
    
    // MARK: - Private
}
