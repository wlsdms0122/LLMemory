//
//  IndexVerifyIntegrity.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct IndexVerifyIntegrity: AsyncParsableCommand {
    struct CheckOutput: Encodable {
        // MARK: - Property
        let ok: Bool
        let level: Int
        let messages: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "integrity",
        abstract: "Multi-level integrity check.",
        discussion: """
            Each level includes the lower ones.
            
            LEVELS
                0   schema shape (tables/columns/indexes match code)
                1   row presence (frontmatter ↔ DB row parity)
                2   FTS5 in sync with notes
                3   semantic checks (tag vocab, id format)
                4   (no L4 checks — derived caches removed)
            
            EXIT STATUS
                0   OK
                1   FAIL
            
            EXAMPLES
                llmemory index verify integrity --level 2 --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Highest level to run (0..4, default 1).")
    var level: Indexer.IntegrityLevel = .l1
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let (ok, messages) = try await brain.index.check(level: level)
        
        CommandOutput().render(
            CheckOutput(ok: ok, level: level.rawValue, messages: messages),
            json: format.json
        ) { output in
            [.text((output.messages + [output.ok ? "OK" : "FAIL"]).joined(separator: "\n"))]
        }
        
        if !ok { throw ExitCode(1) }
    }
    
    // MARK: - Private
}
