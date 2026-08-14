//
//  IndexVerifySources.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct IndexVerifySources: AsyncParsableCommand {
    struct VerifyOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case total, rechecked, recovered, missing, unreadable
            case stillFresh = "still_fresh"
            case becameStale = "became_stale"
        }
        
        // MARK: - Property
        let total: Int
        let rechecked: Int
        let stillFresh: Int
        let becameStale: Int
        let recovered: Int
        let missing: Int
        let unreadable: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "sources",
        abstract: "Recompute source fingerprints and flag drift.",
        discussion: """
            Reads each note's frontmatter `source:` paths, hashes their
            current contents, and compares with the stored baseline. Notes
            whose sources changed get source_stale=1.

            Drift signals review — it does not auto-invalidate content. Run
            periodically or before consolidate.

            EXIT STATUS
                0  every note with a baseline was checked
                1  one or more notes could not be read, so their sources were
                   not checked

            became_stale is NOT a failure: drift is the signal this command
            exists to raise, and raising it is success.

            EXAMPLES
                llmemory index verify sources --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let result = try await brain.index.verifySources()
        let output = VerifyOutput(
            total: result.total,
            rechecked: result.rechecked,
            stillFresh: result.stillFresh,
            becameStale: result.becameStale,
            recovered: result.recovered,
            missing: result.missing,
            unreadable: result.unreadable
        )
        
        CommandOutput().render(output, json: format.json) { output -> [PlainBlock] in
            let pairs: [(String, String)] = [
                ("total", String(output.total)),
                ("rechecked (of total)", String(output.rechecked)),
                ("still_fresh (of rechecked)", String(output.stillFresh)),
                ("became_stale", String(output.becameStale)),
                ("recovered", String(output.recovered)),
                ("missing", String(output.missing)),
                ("unreadable (not checked)", String(output.unreadable.count))
            ]
            var blocks: [PlainBlock] = [.keyValue(pairs)]
            
            if !output.unreadable.isEmpty {
                blocks.append(.text(output.unreadable.joined(separator: "\n")))
            }
            
            return blocks
        }
        
        if !result.unreadable.isEmpty { throw ExitCode(1) }
    }
    
    // MARK: - Private
}
