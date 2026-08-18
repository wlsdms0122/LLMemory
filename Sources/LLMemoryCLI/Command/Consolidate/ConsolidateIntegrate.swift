//
//  ConsolidateIntegrate.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct ConsolidateIntegrate: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "integrate",
        abstract: "(A) Non-destructive upkeep — no decay.",
        discussion: """
            LLM-free, idempotent. Safe to run frequently (e.g. hourly) and for
            recovery — never decays links.
            Default output is plain text; --json emits the typed summary.
            
            EXAMPLES
                llmemory consolidate integrate --home brain
                llmemory consolidate integrate --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = try await Brain.open(home: global.home)
        
        let result = try await brain.consolidate.integrate()
        
        ConsolidateSummaryOutput().emit(result.summary, json: format.json)
    }
    
    // MARK: - Private
}
