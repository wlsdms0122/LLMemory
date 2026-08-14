//
//  IndexVerifyTerms.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct IndexVerifyTerms: AsyncParsableCommand {
    struct ValidateOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case activated, rejected
            case stillPending = "still_pending"
            case staleRejected = "stale_rejected"
            case rejectBreakdown = "reject_breakdown"
        }
        
        // MARK: - Property
        let activated: Int
        let rejected: Int
        let stillPending: Int
        let staleRejected: Int
        let rejectBreakdown: [String: Int]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "terms",
        abstract: "Run llmemory's own validation pass over pending retrieval terms.",
        discussion: """
            Retrieval terms (alias/cue) emitted by `operations apply add_retrieval_terms`
            land as status=pending. This pass is the gate that promotes them —
            llmemory decides, never the LLM:
              
              form         all-stopword / malformed terms → rejected.
              IDF (alias)  tokens whose document-frequency exceeds
                           enrich.idf_df_ceiling are too common to discriminate
                           → rejected (idf_common — the real pollution guard).
                           Tokens absent from both the corpus and the domain
                           vocab cannot be told apart from hallucination by
                           code, so they are kept pending as a quarantine —
                           never hard-rejected.
              round-trip   the term is provisionally indexed into the note's
                           enrich cell, then searched via the real FTS5
                           pipeline; the note must land in top-K (config
                           enrich.roundtrip_topk). Provisional indexing is what
                           lets a genuine synonym — one absent from the note
                           body — still activate.
            
            Outcomes: pass → active (indexed into notes_fts.enrich, searchable
            with zero read-time LLM cost); idf_common / malformed → rejected;
            unverifiable (quarantined) or round-trip fail → kept pending and
            retried — `--reject-stale` finalizes terms stuck pending past the
            age cutoff as rejected (aging is how an unsubstantiated quarantine
            resolves).
            
            `operations apply` already runs this immediately for terms it just inserted;
            `consolidate integrate` runs it periodically. Use this command to
            force a pass (e.g. after a bulk reindex changed the corpus).
            
            EXAMPLES
                llmemory index verify terms --home brain
                llmemory index verify terms --reject-stale --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Flag(name: .long, help: "Finalize long-pending terms as rejected (round-trip never passed).")
    var rejectStale: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let validation = try await brain.index.validateTerms(rejectStale: rejectStale)
        let result = ValidateOutput(
            activated: validation.activated,
            rejected: validation.rejected,
            stillPending: validation.stillPending,
            staleRejected: validation.staleRejected,
            rejectBreakdown: validation.rejectBreakdown
        )
        
        CommandOutput().render(result, json: format.json) { result in
            var blocks: [PlainBlock] = [
                .text("validated: \(result.activated) activated, \(result.rejected) rejected, \(result.stillPending) still pending")
            ]
            
            if result.staleRejected > 0 {
                blocks.append(.text("stale-rejected: \(result.staleRejected)"))
            }
            
            if !result.rejectBreakdown.isEmpty {
                blocks.append(
                    .keyValue(
                        result.rejectBreakdown
                            .sorted { lhs, rhs in lhs.key < rhs.key }
                            .map { entry in (entry.key, String(entry.value)) }
                    )
                )
            }
            
            return blocks
        }
    }
    
    // MARK: - Private
}
