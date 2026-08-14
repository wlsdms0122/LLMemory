//
//  ConsolidateReport.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct ConsolidateReport: AsyncParsableCommand {
    struct TagRow: Encodable {
        // MARK: - Property
        let tag: String
        let count: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct ReportOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case rareTags = "rare_tags"
            case unusedTags = "unused_tags"
        }
        
        // MARK: - Property
        let rareTags: [TagRow]
        let unusedTags: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Tag health report (plain text).",
        discussion: """
            Surfaces rare tags (<=1 use) and unused vocab tags. What the id
            hierarchy looks like is `query tree`'s question, not this one — a
            branch holding one note is normal now, not a finding.
            
            EXAMPLES
                llmemory consolidate report --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let tagReport = try await brain.consolidate.report()
        let report = ReportOutput(
            rareTags: tagReport.rare.map { entry in
                TagRow(tag: entry.tag, count: entry.count)
            },
            unusedTags: tagReport.unused
        )
        
        CommandOutput().render(report, json: format.json) { report in
            var blocks: [PlainBlock] = []
            
            blocks.append(.section("rare tags (<=1)"))
            blocks.append(
                .table(
                    report.rareTags.map { row in [row.tag, String(row.count)] },
                    headers: ["tag", "count"]
                )
            )
            
            if !report.unusedTags.isEmpty {
                blocks.append(.section("unused vocab tags"))
                blocks.append(
                    .text(report.unusedTags.map { tag in "  \(tag)" }.joined(separator: "\n"))
                )
            }
            
            return blocks
        }
    }
    
    // MARK: - Private
}
