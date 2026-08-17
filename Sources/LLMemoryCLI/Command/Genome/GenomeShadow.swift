//
//  GenomeShadow.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct GenomeShadow: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "shadow",
        abstract: "Replay logged queries under a candidate gene value — offline reranking, not a counterfactual.",
        discussion: """
            Honest db, by design:
              · raw-retention only — replays search/related retrieval events
                still in the events table; compacted history is gone and no
                replay ledger exists.
              · both runs use the CURRENT corpus — the diff isolates the gene
                change; it does not claim what a past session would have been
                (the agent's next query would have differed).
              · search + related's read-only core — related replays skip the
                rebirth write half (dryRun), so introspection never rehearses
                edges.
            
            EXAMPLES
                llmemory genome shadow --gene links.sibling_rank_weight --value 0.15 --home brain
                llmemory genome shadow --gene priming.alpha --value 1.0 --limit 100 --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Gene id from `genome list`.")
    var gene: String
    
    @Option(name: .long, help: "Candidate value (within the gene's bounds).")
    var value: Double
    
    @Option(name: .long, help: "Max logged queries to replay (default 50).")
    var limit: Int = 50
    
    @Option(name: .long, help: "Max per-query diffs to include (default 5).")
    var sampleDiffs: Int = 5
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let result = try await brain.genome.shadow(
            gene: gene,
            value: value,
            limit: limit,
            sampleDiffs: sampleDiffs
        )
        
        CommandOutput().render(result, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .keyValue([
                    ("gene", output.gene),
                    ("baseline", String(format: "%g", output.baselineValue)),
                    ("candidate", String(format: "%g", output.candidateValue)),
                    ("queries_replayed", String(output.queriesReplayed)),
                    ("queries_changed", String(output.queriesChanged))
                ])
            ]
            
            for diff in output.diffs {
                blocks.append(.section("query: \(diff.query)"))
                blocks.append(
                    .keyValue([
                        ("baseline", diff.baseline.joined(separator: ", ")),
                        ("candidate", diff.candidate.joined(separator: ", ")),
                        ("entered", diff.entered.joined(separator: ", ")),
                        ("dropped", diff.dropped.joined(separator: ", "))
                    ])
                )
            }
            
            return blocks
        }
    }
    
    // MARK: - Private
}
