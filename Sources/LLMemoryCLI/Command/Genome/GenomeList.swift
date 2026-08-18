//
//  GenomeList.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct GenomeList: AsyncParsableCommand {
    struct Output: Encodable {
        // MARK: - Property
        let genes: [GeneListRow]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "The gene catalog with effective values and their provenance.",
        discussion: """
            `source` says where each effective value comes from: genome (a
            per-brain row), config (legacy config.* meta override), or
            wild_type. `mutable` marks the genes homeostasis may adjust —
            locked genes are write-path: their past effect is baked into
            persistent structure, so reverting the value does not revert the
            brain; only the direct set_gene op may move them.
            
            EXAMPLES
                llmemory genome list --home brain
                llmemory genome list --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = try await Brain.open(home: global.home)
        
        let rows = try await brain.genome.list()
        
        CommandOutput().render(Output(genes: rows), json: format.json) { output in
            [
                .table(
                    output.genes.map { gene in
                        [
                            gene.id,
                            String(format: "%g", gene.value),
                            String(format: "%g", gene.wildType),
                            "[\(String(format: "%g", gene.min)), \(String(format: "%g", gene.max))]",
                            gene.mutable ? "mutable" : "locked",
                            gene.source,
                            gene.summary
                        ]
                    },
                    headers: [
                        "gene", "value", "wild", "bounds", "plasticity", "source", "summary"
                    ]
                )
            ]
        }
    }
    
    // MARK: - Private
}
