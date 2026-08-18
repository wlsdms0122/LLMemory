//
//  QueryList.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryList: AsyncParsableCommand {
    struct Row: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, title, summary, priority, stale
            case sourceStale = "source_stale"
            case createdAt = "created_at"
            case editedAt = "edited_at"
        }
        
        // MARK: - Property
        let id, title: String
        let summary: String?
        let priority: String?
        let stale, sourceStale: Bool?
        let createdAt, editedAt: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "Enumerate notes matching composable filters.",
        discussion: """
            Pure enumeration — no ranking. Each flag is one AND-composed
            predicate; absent flags don't constrain. For ranked retrieval
            use `search` or `related`.
            
            Plain output is a table (id, title, summary). For scripted
            id extraction use --json (adds lifecycle fields) and parse.
            
            
            EXAMPLES
                llmemory query list --priority eager --home brain
                llmemory query list --stale --tag persona --home brain
                llmemory query list --tag skill --json --home brain
                llmemory query list --tag journal --field affect=high --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Match a priority (e.g. eager).")
    var priority: String?
    
    @Option(name: .long, help: "Match a tag. Repeatable — all must be present.")
    var tag: [String] = []
    
    @Option(name: .long, help: "Match a custom frontmatter field: 'key' (present) or 'key=value'. Repeatable.")
    var field: [String] = []
    
    @Flag(name: .long, help: "Match content-stale notes (stale = 1).")
    var stale: Bool = false
    
    @Flag(name: .long, help: "Match source-stale notes (source_stale = 1).")
    var sourceStale: Bool = false
    
    @Option(name: .long, help: "Cap rows returned (default: no cap).")
    var limit: Int?
    
    @Flag(name: .long, help: "Raise the data level: adds priority, lifecycle flags, and created/edited timestamps — same fields in plain and --json.")
    var verbose: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = try await Brain.open(home: global.home)
        
        let rows = try await brain.query.list(
            priority: priority,
            tags: tag,
            fields: try field.map { spec in try Self.parseField(spec) },
            stale: stale,
            sourceStale: sourceStale,
            limit: limit
        )
        let output = rows.map { row in
            Row(
                id: row.id,
                title: row.title,
                summary: row.summary,
                priority: verbose ? row.priority : nil,
                stale: verbose ? row.stale : nil,
                sourceStale: verbose ? row.sourceStale : nil,
                createdAt: verbose ? row.createdAt : nil,
                editedAt: verbose ? row.editedAt : nil
            )
        }
        
        CommandOutput().render(output, json: format.json) { rows -> [PlainBlock] in
            guard verbose else {
                return [
                    .table(
                        rows.map { row in [row.id, row.title, row.summary ?? ""] },
                        headers: ["id", "title", "summary"]
                    )
                ]
            }
            
            return [
                .table(
                    rows.map { row in
                        let flags = [
                            row.stale == true ? "stale" : nil,
                            row.sourceStale == true ? "src-stale" : nil
                        ].compactMap { flag in flag }
                        
                        return [
                            row.id,
                            row.priority ?? "",
                            flags.joined(separator: ","),
                            DayStamp().dayString(row.createdAt ?? 0),
                            DayStamp().dayString(row.editedAt ?? 0),
                            row.title,
                            row.summary ?? ""
                        ]
                    },
                    headers: [
                        "id", "priority", "flags", "created", "edited", "title", "summary"
                    ]
                )
            ]
        }
    }
    
    // MARK: - Private
    private static func parseField(_ spec: String) throws -> NoteFieldFilter {
        guard let separator = spec.firstIndex(of: "=") else {
            guard !spec.isEmpty else {
                throw ValidationError("--field needs a key: 'key' or 'key=value'")
            }
            
            return NoteFieldFilter(key: spec, value: nil)
        }
        
        let key = String(spec[spec.startIndex..<separator])
        let value = String(spec[spec.index(after: separator)...])
        
        guard !key.isEmpty, !value.isEmpty else {
            throw ValidationError("--field '\(spec)' must be 'key' or 'key=value'")
        }
        
        return NoteFieldFilter(key: key, value: value)
    }
}
