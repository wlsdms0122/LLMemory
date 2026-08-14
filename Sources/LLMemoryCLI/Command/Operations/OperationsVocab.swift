//
//  OperationsVocab.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

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
            
            CommandOutput().render(VerboseOutput(ops: rows), json: format.json) { output in
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
            CommandOutput().render(Output(ops: brain.operations.operationNames()), json: format.json) { output in
                [.text(output.ops.joined(separator: "\n"))]
            }
        }
    }
    
    // MARK: - Private
}
