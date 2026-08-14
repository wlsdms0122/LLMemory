//
//  QueryNeighbors.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryNeighbors: AsyncParsableCommand {
    struct Item: Encodable {
        // MARK: - Property
        let id: String
        let title: String
        let summary: String?
        let score: Double
        let fts: Double?
        let entity: Double?
        let link: Double?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "neighbors",
        abstract: "Composite-ranked neighbors of one note (FTS + entity + link).",
        discussion: """
            Score = round(fts + entity + link, 4). Ties broken by id ascending.
            Use when you have a known anchor; for free-form text use `related`.
            
            EXAMPLES
                llmemory query neighbors --id principles --k 8 --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Anchor note id.")
    var id: String
    
    @Option(name: .long, help: "Top-K neighbors (default 10).")
    var k: Int = 10
    
    @Flag(name: .long, help: "Raise the data level: adds fts/entity/link score components — same fields in plain and --json.")
    var verbose: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let scores = try await brain.query.neighbors(
            id: id,
            k: k,
            cliSessionId: global.sessionId
        )
        let items = scores.map { score in
            Item(
                id: score.id,
                title: score.title,
                summary: score.summary,
                score: score.score,
                fts: verbose ? score.fts : nil,
                entity: verbose ? score.entity : nil,
                link: verbose ? score.link : nil
            )
        }
        
        CommandOutput().render(items, json: format.json) { items -> [PlainBlock] in
            guard verbose else {
                return [
                    .table(
                        items.map { item in
                            [
                                item.id,
                                String(format: "%.2f", item.score),
                                item.title,
                                item.summary ?? ""
                            ]
                        },
                        headers: ["id", "score", "title", "summary"]
                    )
                ]
            }
            
            return [
                .table(
                    items.map { item in
                        [
                            item.id,
                            String(format: "%.2f", item.score),
                            String(format: "%.2f", item.fts ?? 0),
                            String(format: "%.2f", item.entity ?? 0),
                            String(format: "%.2f", item.link ?? 0),
                            item.title,
                            item.summary ?? ""
                        ]
                    },
                    headers: [
                        "id", "score", "fts", "entity", "link", "title", "summary"
                    ]
                )
            ]
        }
    }
    
    // MARK: - Private
}
