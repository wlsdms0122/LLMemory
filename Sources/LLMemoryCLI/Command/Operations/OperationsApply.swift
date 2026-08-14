//
//  OperationsApply.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct OperationsApply: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Apply a transaction of ops atomically.",
        discussion: """
            Reads a transaction from --input or stdin, validates and applies
            inside a single SAVEPOINT, rolls back DB and file snapshots on failure.

            PAYLOAD
                {"ops": [<op>, ...], "rationale": "..."}

                Each <op> is a dict whose `op` field names a handler.
                Run `operations vocab` for handlers; `operations describe <op>` for fields.

            EXIT STATUS
                0   status == "ok"
                1   status != "ok"
                2   missing or invalid JSON

            EXAMPLES
                echo '{"ops":[{"op":"invalidate","id":"old","reason":"superseded"}],"rationale":"stale"}' \\
                    | llmemory operations apply --home brain

                llmemory operations apply --home brain --input "$(cat plan.json)"

            SEE ALSO
                operations dry-run, operations vocab, operations describe
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
        
        let result = await brain.operations.apply(
            payloadJSON: payload,
            cliSessionId: global.sessionId
        )
        
        CommandOutput().render(result, json: format.json) { result in OperationsResultBlocks().blocks(of: result) }
        
        if result.status != "ok" { throw ExitCode(1) }
    }
    
    // MARK: - Private
}
