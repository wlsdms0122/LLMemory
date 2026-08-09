//
//  Operations.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct OperationsCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "operations",
        abstract: "Atomic write transactions — all mutations go through here.",
        discussion: """
            All file and DB writes go through `apply`. Each transaction validates
            every op, snapshots affected files, applies inside a single SAVEPOINT,
            and rolls back DB and files on any failure. No direct file or row edits.

            The canonical spelling is `operations`; `ops` reaches the same
            group as an alias.

            SEE ALSO
                operations apply, operations vocab, operations describe
            """,
        subcommands: [OperationsApply.self, OperationsDryRun.self, OperationsVocab.self, OperationsDescribe.self],
        // Owner call: the surface may stay short — `ops` aliases the
        // spelled-out internal name, and both forms reach the same command.
        aliases: ["ops"]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

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
    @OptionGroup var rulesetOption: RulesetOption
    
    @Option(name: .long, help: "Transaction JSON. Reads stdin if omitted.")
    var input: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        guard let payload = try readJSONText(input) else { throw ExitCode(2) }
        
        let result = await brain.operations.apply(
            payloadJSON: payload,
            cliSessionId: global.sessionId,
            ruleset: rulesetOption.rulesetId
        )
        
        render(result, json: format.json) { result in opsResultBlocks(result) }
        
        if result.status != "ok" { throw ExitCode(1) }
    }
    
    // MARK: - Private
}

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
    @OptionGroup var rulesetOption: RulesetOption
    
    @Option(name: .long, help: "Transaction JSON. Reads stdin if omitted.")
    var input: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        guard let payload = try readJSONText(input) else { throw ExitCode(2) }
        
        let result = await brain.operations.dryRun(
            payloadJSON: payload,
            cliSessionId: global.sessionId,
            ruleset: rulesetOption.rulesetId
        )
        
        render(result, json: format.json) { result in opsResultBlocks(result) }
        
        if result.status != "ok" { throw ExitCode(1) }
    }
    
    // MARK: - Private
}

struct OperationsVocab: ParsableCommand {
    struct Output: Encodable {
        // MARK: - Property
        let ops: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct VerboseOp: Encodable {
        // MARK: - Property
        let name: String
        let summary: String
        let required: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct VerboseOutput: Encodable {
        // MARK: - Property
        let ops: [VerboseOp]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "vocab",
        abstract: "List registered op names.",
        discussion: """
            Authoritative catalog of op handlers. Use --verbose for each op's
            summary and required fields.

            EXAMPLES
                llmemory operations vocab --home brain
                llmemory operations vocab --verbose --home brain

            SEE ALSO
                operations describe
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Flag(name: .shortAndLong, help: "Include per-op summary + required fields.")
    var verbose: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let brain = Brain(home: global.home)
        
        if verbose {
            let rows = brain.operations.operationNames().compactMap { name -> VerboseOp? in
                guard let schema = brain.operations.operationSchema(name) else { return nil }
                
                return VerboseOp(
                    name: name,
                    summary: schema.summary,
                    required: schema.requiredNames
                )
            }
            
            render(VerboseOutput(ops: rows), json: format.json) { output in
                [
                    .table(
                        output.ops.map { op in
                            [op.name, op.required.joined(separator: ","), op.summary]
                        },
                        headers: ["op", "required", "summary"]
                    )
                ]
            }
        } else {
            render(Output(ops: brain.operations.operationNames()), json: format.json) { output in
                [.text(output.ops.joined(separator: "\n"))]
            }
        }
    }
    
    // MARK: - Private
}

struct OperationsDescribe: ParsableCommand {
    struct Output: Encodable {
        // MARK: - Property
        let name: String
        let summary: String
        let fields: [OpField]
        let example: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "describe",
        abstract: "Show field schema and example for one op.",
        discussion: """
            Plain-text output groups fields by required/optional and prints
            an apply-ready payload. Use --json for machine-readable output;
            in that mode `example` is the bare op (wrap as
            {"ops":[<example>]} before passing to `apply`).

            EXAMPLES
                llmemory operations describe patch_section --home brain
                llmemory operations describe patch_section --json --home brain

            SEE ALSO
                operations apply, operations vocab
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Argument(help: "Op name (must appear in `operations vocab`).")
    var op: String
    
    // MARK: - Initializer
    // MARK: - Public
    func run() throws {
        let brain = Brain(home: global.home)
        
        guard let schema = brain.operations.operationSchema(op) else {
            FileHandle.standardError.write(
                "unknown op: \(op) (see `operations vocab`)\n".data(using: .utf8) ?? Data()
            )
            
            throw ExitCode(1)
        }
        
        let output = Output(
            name: op,
            summary: schema.summary,
            fields: schema.fields,
            example: schema.example
        )
        
        render(output, json: format.json) { output in
            var lines: [String] = ["\(output.name) — \(output.summary)", ""]
            let required = output.fields.filter(\.required)
            let optional = output.fields.filter { field in !field.required }
            let nameWidth = max(
                required.map { field in field.name.displayWidth }.max() ?? 0,
                optional.map { field in field.name.displayWidth }.max() ?? 0,
                4
            )
            
            func fieldLine(_ field: OpField) -> String {
                let padding = String(
                    repeating: " ",
                    count: max(0, nameWidth - field.name.displayWidth)
                )
                
                return "  \(field.name)\(padding)  \(field.description)"
            }
            
            if !required.isEmpty {
                lines.append("Required:")
                lines.append(contentsOf: required.map(fieldLine))
            }
            
            if !optional.isEmpty {
                if !required.isEmpty { lines.append("") }
                
                lines.append("Optional:")
                lines.append(contentsOf: optional.map(fieldLine))
            }
            
            lines.append("")
            lines.append("Apply payload:")
            lines.append("  {\"ops\":[\(output.example)],\"rationale\":\"...\"}")
            
            return [.text(lines.joined(separator: "\n"))]
        }
    }
    
    // MARK: - Private
}

private func opsResultBlocks(_ result: OperationsResult) -> [PlainBlock] {
    var blocks: [PlainBlock] = [
        .text(result.status == "ok"
            ? "ok  (\(result.opResults.count) ops)"
            : "\(result.status)\(result.error.isEmpty ? "" : ": \(result.error)")")
    ]
    
    if let rejectedIndex = result.rejectedIndex {
        blocks.append(.text("rejected_index: \(rejectedIndex)"))
    }
    
    if !result.recoveryFailed.isEmpty {
        blocks.append(
            .text("recovery_failed: \(result.recoveryFailed.joined(separator: ", "))")
        )
    }
    
    return blocks
}

private func opsResultBlocks(_ result: OperationsDryRunResult) -> [PlainBlock] {
    let suffix = result.opCount.map { count in "  (\(count) ops)" } ?? ""
    var blocks: [PlainBlock] = []
    
    if let error = result.error, !error.isEmpty {
        blocks.append(.text("\(result.status): \(error)\(suffix)"))
    } else {
        blocks.append(.text("\(result.status)\(suffix)"))
    }
    
    if let rejectedIndex = result.rejectedIndex {
        blocks.append(.text("rejected_index: \(rejectedIndex)"))
    }
    
    return blocks
}
