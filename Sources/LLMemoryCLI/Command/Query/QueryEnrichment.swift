//
//  QueryEnrichment.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryEnrichment: AsyncParsableCommand {
    struct TermCount: Encodable {
        // MARK: - Property
        let kind, status: String
        let count: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct ProvenanceRow: Encodable {
        enum CodingKeys: String, CodingKey {
            case provenance, alarm
            case assocEdges = "assoc_edges"
            case disagreeEdges = "disagree_edges"
            case disagreeRate = "disagree_rate"
        }
        
        // MARK: - Property
        let provenance: String
        let assocEdges: Int
        let disagreeEdges: Int
        let disagreeRate: Double
        let alarm: Bool
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Output: Encodable {
        enum CodingKeys: String, CodingKey {
            case provenance
            case retrievalTerms = "retrieval_terms"
            case assocTotal = "assoc_total"
            case assocActive = "assoc_active"
            case assocDormant = "assoc_dormant"
            case vectorsBuiltAt = "vectors_built_at"
            case vectorsDim = "vectors_dim"
            case noteCount = "note_count"
            case vectorCount = "vector_count"
            case vectorCoverage = "vector_coverage"
            case reviewFlagged = "review_flagged"
        }
        
        // MARK: - Property
        let retrievalTerms: [TermCount]
        let assocTotal: Int
        let assocActive: Int
        let assocDormant: Int
        let vectorsBuiltAt: Int?
        let vectorsDim: Int?
        let noteCount: Int
        let vectorCount: Int
        let vectorCoverage: Double
        let provenance: [ProvenanceRow]
        let reviewFlagged: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "enrichment",
        abstract: "Observe the semantic-enrichment layer's runtime state.",
        discussion: """
            Makes the enrichment design observable, not just declared — so a
            port to another system can verify it is alive at a glance.

            REPORTS
                retrieval terms   alias/cue counts by status. pending = awaiting
                                  validation; active = passed round-trip + IDF
                                  and indexed into notes_fts.enrich; rejected =
                                  filtered (reason in note_retrieval_terms).
                assoc edges       LLM-proposed semantic edges: total, active
                                  (strengthened past the 0.5 traversal floor by
                                  co-retrieval), dormant (still below it; decay
                                  will prune if never used).
                vectors           build time, dim, and coverage (notes with a
                                  note_vectors row ÷ total notes).
                provenance        per-producer assoc-edge disagreement rate
                                  (share whose two notes are far apart in vector
                                  space). A rate above enrich.model_alarm_rate
                                  flags a possibly-noisy model — catches
                                  regressions when the capture model changes.

            EXAMPLES
                llmemory query enrichment --home brain
                llmemory query enrichment --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let status = try await brain.query.enrichment()
        let output = Output(
            retrievalTerms: status.termCounts.map { term in
                TermCount(kind: term.kind, status: term.status, count: term.count)
            },
            assocTotal: status.assocTotal,
            assocActive: status.assocActive,
            assocDormant: status.assocDormant,
            vectorsBuiltAt: status.vectorsBuiltAt,
            vectorsDim: status.vectorsDim,
            noteCount: status.noteCount,
            vectorCount: status.vectorCount,
            vectorCoverage: (status.vectorCoverage * 1000).rounded() / 1000,
            provenance: status.provenanceStats.map { stat in
                ProvenanceRow(
                    provenance: stat.provenance,
                    assocEdges: stat.assocEdges,
                    disagreeEdges: stat.disagreeEdges,
                    disagreeRate: (stat.disagreeRate * 1000).rounded() / 1000,
                    alarm: stat.alarm
                )
            },
            reviewFlagged: status.reviewFlagged
        )
        
        CommandOutput().render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [.section("retrieval terms")]
            
            blocks.append(
                .table(
                    output.retrievalTerms.map { term in
                        [term.kind, term.status, String(term.count)]
                    },
                    headers: ["kind", "status", "count"]
                )
            )
            blocks.append(.section("assoc edges"))
            blocks.append(
                .keyValue([
                    ("total", String(output.assocTotal)),
                    ("active (>= floor)", String(output.assocActive)),
                    ("dormant (< floor)", String(output.assocDormant))
                ])
            )
            blocks.append(.section("vectors"))
            blocks.append(
                .keyValue([
                    ("built_at", output.vectorsBuiltAt.map(String.init) ?? "(never)"),
                    ("dim", output.vectorsDim.map(String.init) ?? "-"),
                    (
                        "coverage",
                        "\(output.vectorCount)/\(output.noteCount) (\(String(format: "%.0f%%", output.vectorCoverage * 100)))"
                    )
                ])
            )
            blocks.append(.section("provenance disagreement"))
            blocks.append(
                .table(
                    output.provenance.map { row in
                        [
                            row.provenance,
                            String(row.assocEdges),
                            String(row.disagreeEdges),
                            String(format: "%.2f", row.disagreeRate),
                            row.alarm ? "ALARM" : ""
                        ]
                    },
                    headers: ["provenance", "edges", "disagree", "rate", "flag"]
                )
            )
            blocks.append(.section("review queue"))
            blocks.append(
                .text("  enrich_review flagged (unresolved): \(output.reviewFlagged)")
            )
            
            return blocks
        }
    }
    
    // MARK: - Private
}
