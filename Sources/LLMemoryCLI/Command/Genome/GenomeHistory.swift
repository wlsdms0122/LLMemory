//
//  GenomeHistory.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct GenomeHistory: AsyncParsableCommand {
    struct Output: Encodable {
        // MARK: - Property
        let events: [GeneHistoryRow]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Gene change provenance — who moved what, when, and why.",
        discussion: """
            Every genome write (set_gene / homeostasis) lands one event row.
            cause is the door it came through; detail carries the reason or the
            rule's evidence (rate, sample size).
            
            EXAMPLES
                llmemory genome history --home brain
                llmemory genome history --gene related.expand_hops --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Filter to one gene id.")
    var gene: String?
    
    @Option(name: .long, help: "Max events (default 50).")
    var limit: Int = 50
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let rows = try await brain.genome.history(gene: gene, limit: limit)
        
        CommandOutput().render(Output(events: rows), json: format.json) { output in
            [
                .table(
                    output.events.map { event in
                        [
                            String(event.ts),
                            event.geneId,
                            event.oldValue.map { value in String(format: "%g", value) } ?? "-",
                            String(format: "%g", event.newValue),
                            event.cause,
                            event.detail ?? ""
                        ]
                    },
                    headers: ["ts", "gene", "old", "new", "cause", "detail"]
                )
            ]
        }
    }
    
    // MARK: - Private
}
