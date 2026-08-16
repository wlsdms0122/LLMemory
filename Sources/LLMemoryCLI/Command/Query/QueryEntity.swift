//
//  QueryEntity.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryEntity: AsyncParsableCommand {
    // The command owns its JSON shape — the module's EntityHit carries
    // title for retrieval, but this surface never printed it.
    struct Row: Encodable {
        enum CodingKeys: String, CodingKey {
            case entity, summary
            case noteId = "note_id"
            case lastSeenAt = "last_seen_at"
            case hitCount = "hit_count"
        }
        
        // MARK: - Property
        let entity: String
        let noteId: String
        let summary: String?
        let lastSeenAt: Int
        let hitCount: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "entity",
        abstract: "Reverse lookup: entity → notes.",
        discussion: """
            NoteFile mentioning an entity in body, ordered by last_seen_at. Used
            by retrieval to surface notes sharing named entities when keyword
            overlap is low.
            
            EXAMPLES
                llmemory query entity TossDI --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Argument(help: "Entity name (omit to list all entities).")
    var name: String?
    
    @Option(name: .long, help: "Max rows (default 30).")
    var limit: Int = 30
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let hits = try await brain.query.entity(name: name, limit: limit)
        let rows = hits.map { hit in
            Row(
                entity: hit.entity,
                noteId: hit.noteId,
                summary: hit.summary,
                lastSeenAt: hit.lastSeenAt,
                hitCount: hit.hitCount
            )
        }
        
        CommandOutput().render(rows, json: format.json) { rows in
            [
                .table(
                    rows.map { row in
                        [
                            row.entity,
                            row.noteId,
                            String(row.hitCount),
                            row.summary ?? ""
                        ]
                    },
                    headers: ["entity", "note_id", "hits", "summary"]
                )
            ]
        }
    }
    
    // MARK: - Private
}
