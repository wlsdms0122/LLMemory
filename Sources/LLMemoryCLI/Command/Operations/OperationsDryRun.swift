//
//  OperationsDryRun.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct OperationsDryRun: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "dry-run",
        abstract: "Validate a transaction without persisting.",
        discussion: """
            Runs the same validation as `apply` but commits nothing.

            EXIT STATUS
                0   validation passed
                1   validation failed
                2   missing or invalid JSON

            EXAMPLES
                llmemory operations dry-run --home brain --json '<payload>'

            SEE ALSO
                operations apply
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    @Option(name: .long, help: "Transaction JSON. Reads stdin if omitted.")
    var input: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        guard let payload = try CommandInput().readJSONText(input) else { throw ExitCode(2) }
        
        let result = await brain.operations.dryRun(
            payloadJSON: payload,
            cliSessionId: global.sessionId
        )
        
        CommandOutput().render(result, json: format.json) { result in OperationsResultBlocks().blocks(of: result) }
        
        if result.status != "ok" { throw ExitCode(1) }
    }
    
    // MARK: - Private
}
