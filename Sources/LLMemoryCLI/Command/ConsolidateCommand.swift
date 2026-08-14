//
//  ConsolidateCommand.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct ConsolidateCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "consolidate",
        abstract: "Consolidation domain — mutating upkeep + read-only planning (LLM-free).",
        discussion: """
            The consolidation domain has two halves. The MUTATING ops are three
            independent upkeep passes, each its own concern and cadence — never
            bundled at the engine level (the caller composes them):

              · integrate (A) — non-destructive upkeep: events compaction,
                source verify, prune, integrity L1, term validation, enrich
                review, vector rebuild. Idempotent, safe to run often.
              · prune (B) — destructive decay: learned link weights decayed,
                links pruned below floor. One call = one subjective-time tick.
              · homeostasis (H) — deterministic meta-plasticity: consumes
                closed activity windows exactly once and may adjust ONE
                mutable read-path gene within bounds (see `genome list`).

            The READ-ONLY surfaces plan and inspect that upkeep (no writes):
            candidates (restructure/cleanup candidates the agent acts on) and
            report (tag health).

            SEMANTIC ENRICHMENT LIFECYCLE (integrate)
                integrate drives the deterministic side of enrichment (LLM
                emits via capture; llmemory owns slots, validation, retrieval):
                  · retrieval terms — round-trip + IDF validation pass
                    (terms_activated / terms_rejected); terms stuck pending past
                    the age cutoff are finalized as rejected.
                  · assoc edges — the link decay/strengthen loop IS their
                    validator (decay lives in `prune`, not here).
                  · ensemble disagreement — assoc edges far apart in note_vectors
                    are quarantined with an enrich_review ripple flag; a pass also
                    resolves flags whose disagreement cleared (cosine recovered
                    or edge pruned), so the gauge tracks the live set.
                Observe runtime state with `query enrichment`.

            SEE ALSO
                consolidate integrate, consolidate prune
                consolidate candidates, consolidate report
                query enrichment, index vector, index verify terms
            """,
        subcommands: [
            ConsolidateIntegrate.self,
            ConsolidatePrune.self,
            ConsolidateHomeostasis.self,
            ConsolidateCandidates.self,
            ConsolidateReport.self
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
