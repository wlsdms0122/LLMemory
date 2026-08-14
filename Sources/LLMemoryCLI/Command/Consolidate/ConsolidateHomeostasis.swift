//
//  ConsolidateHomeostasis.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct ConsolidateHomeostasis: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "homeostasis",
        abstract: "(H) Deterministic meta-plasticity tick — adjust mutable genes from the activation trace.",
        discussion: """
            LLM 0. Consumes closed activity windows exactly once (watermark),
            accumulates waste evidence, and when the sample is large enough
            adjusts at most ONE mutable read-path gene by one step within its
            bounds — never past wild-type. Locked (write-path) genes are out of
            reach by construction; move those with the `set_gene` op, with a
            reason, when there is one.

            v1 rule: expansion landing — expand-surfaced notes that are never
            opened (`get`) in their window are dead weight; a persistently ~0
            landing rate narrows `related.expand_hops`, a healthy rate restores
            it toward wild-type.

            Safe at any call frequency: windows are consumed exactly once and
            evidence accumulates across calls until min_sample is reached.

            EXAMPLES
                llmemory consolidate homeostasis --home brain
                llmemory consolidate homeostasis --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let result = try await brain.consolidate.homeostasis()
        
        ConsolidateSummaryOutput().emit(result, json: format.json)
    }
    
    // MARK: - Private
}
