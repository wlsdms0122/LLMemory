//
//  QueryHistory.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryHistory: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "Lifecycle events for a note.",
        discussion: """
            Reads note_lifecycle_events newest first. Use for auditing changes.
            
            EXAMPLES
                llmemory query history --id principles --limit 20 --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Note id.")
    var id: String
    
    @Option(name: .long, help: "Max rows (default 50).")
    var limit: Int = 50
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let rows = try await brain.query.history(noteId: id, limit: limit)
        
        CommandOutput().render(rows, json: format.json) { rows in
            [
                .table(
                    rows.map { row in [String(row.at), row.kind, row.reason ?? ""] },
                    headers: ["at", "kind", "reason"]
                )
            ]
        }
    }
    
    // MARK: - Private
}
