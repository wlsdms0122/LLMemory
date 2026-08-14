//
//  OperationsDescribe.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

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
        
        CommandOutput().render(output, json: format.json) { output in
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
