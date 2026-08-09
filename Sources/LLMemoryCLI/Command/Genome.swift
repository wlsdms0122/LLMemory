//
//  Genes.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct GenomeCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "genome",
        abstract: "Plasticity-parameter catalog — per-brain values, history, shadow introspection.",
        discussion: """
            The genome is the substrate's parameter layer made data. The
            *declaration* (which genes exist, bounds, wild-type, mutability) is
            code — species-level and versioned with the binary. The *per-brain
            current value* (epigenome) lives in the genome table; a gene without
            a row runs at wild-type.

            Two write doors only:
              · set_gene op (`operations apply`) — direct value set, all genes.
              · consolidate homeostasis — deterministic loop, mutable
                (read-path) genes only.

            SEE ALSO
                genome list, genome history, genome shadow
                consolidate homeostasis, ops describe set_gene
            """,
        subcommands: [GenomeList.self, GenomeHistory.self, GenomeShadow.self]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct GenomeList: AsyncParsableCommand {
    struct Output: Encodable {
        // MARK: - Property
        let genes: [GenomeService.ListRow]
        
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
        let brain = Brain(home: global.home)
        
        let rows = try await brain.genome.list()
        
        render(Output(genes: rows), json: format.json) { output in
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

struct GenomeHistory: AsyncParsableCommand {
    struct Output: Encodable {
        // MARK: - Property
        let events: [GenomeService.HistoryRow]
        
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
        
        render(Output(events: rows), json: format.json) { output in
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

struct GenomeShadow: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "shadow",
        abstract: "Replay logged queries under a candidate gene value — offline reranking, not a counterfactual.",
        discussion: """
            Honest scope, by design:
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
        
        render(result, json: format.json) { output in
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
