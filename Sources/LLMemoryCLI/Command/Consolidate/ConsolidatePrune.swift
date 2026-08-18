//
//  ConsolidatePrune.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct ConsolidatePrune: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "(B) Decay learned link weights, prune below floor.",
        discussion: """
            Destructive. One call is one subjective-time tick — the caller's
            cadence is the clock (this bot only runs when used, so invocation
            count, not wall time, is the right axis). Run sparingly (e.g. with
            the replay flow), not on every integrate pass.
            
            EXAMPLES
                llmemory consolidate prune --home brain
                llmemory consolidate prune --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = try await Brain.open(home: global.home)
        
        let result = try await brain.consolidate.prune()
        
        ConsolidateSummaryOutput().emit(result, json: format.json)
    }
    
    // MARK: - Private
}
