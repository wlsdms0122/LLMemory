//
//  QueryTree.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryTree: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "tree",
        abstract: "One level of the id hierarchy with note counts.",
        discussion: """
            An id is an address — `a.b.c` is the note at cortex/a/b/c.md — so the
            hierarchy is read off the ids themselves, not stored anywhere. This
            shows one level at a time: what branches exist and how much lives
            under each. Descend by passing the branch back as --prefix.

            It answers "where is there anything, and how much", nothing else.
            What a branch is *about* is the tags' answer, and whether a split
            family kept its parent is the lint's.

            EXAMPLES
                llmemory query tree --home brain
                llmemory query tree --prefix journal --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Descend under this id prefix.")
    var prefix: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        let rows = try await brain.query.tree(prefix: prefix)
        
        CommandOutput().render(rows, json: format.json) { rows in
            [
                .table(
                    rows.map { row in [row.prefix, String(row.notes)] },
                    headers: ["prefix", "notes"]
                )
            ]
        }
    }
    
    // MARK: - Private
}
