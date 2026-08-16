//
//  QuerySearch.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QuerySearch: AsyncParsableCommand {
    struct Row: Encodable {
        // MARK: - Property
        let id, title: String
        let summary: String?
        let section: String?
        let path: String?
        let tags: [String]?
        let stale: Bool?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Expanded: Encodable {
        // MARK: - Property
        let id, title: String
        let summary: String?
        let weight: Double
        let path: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Output: Encodable {
        // MARK: - Property
        let rows: [Row]
        let expanded: [Expanded]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Full-text search over title/summary/body (FTS5).",
        discussion: """
            By default the query is tokenized and matched as an OR of its terms
            (recall-oriented, same model as `query related`); bm25 ranks notes
            matching more/rarer terms first. This is what you want for natural
            multi-keyword queries — wrapping the whole string as one phrase (the
            old behavior) only matched notes containing those tokens contiguously,
            so multi-word queries almost always returned nothing.
            
            Pass --raw to send the string verbatim as an FTS5 expression
            (AND/OR/NOT/"phrase"/prefix*). Note `-` is the NOT operator, so quote
            hyphenated terms (e.g. '"foo-bar"').
            
            Tags are not in the FTS index — use `query related` for tag/entity-aware
            retrieval.
            
            EXAMPLES
                llmemory query search "ios log masking transformer" --home brain
                llmemory query search "transfer" --tag tech --limit 10 --home brain
                llmemory query search "transfer NOT giro" --raw --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Argument(help: "FTS5 query string.")
    var query: String
    
    @Option(name: .long, help: "Restrict to notes carrying this tag. Repeatable — all must be present.")
    var tag: [String] = []
    
    @Option(name: .long, help: "Max rows returned (default 5).")
    var limit: Int = 5
    
    @Option(name: .long, help: "Pull N additional 2-hop linked notes (default 0).")
    var expand: Int = 0
    
    @Flag(name: .long, help: "Include notes marked stale.")
    var includeStale: Bool = false
    
    @Option(name: .long, parsing: .upToNextOption, help: "Tags to exclude from search.")
    var excludeTags: [String] = []
    
    @Flag(name: .long, help: "Treat the query as a verbatim FTS5 expression (AND/OR/NOT/\"phrase\"/prefix*) instead of tokenizing into an OR.")
    var raw: Bool = false
    
    @Flag(name: .long, help: "Raise the data level: adds path, tags, and stale — same fields in plain and --json.")
    var verbose: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let (rows, extra) = try await brain.query.search(
            query: query,
            tags: tag,
            limit: limit,
            expand: expand,
            sessionId: global.session,
            includeStale: includeStale,
            excludeTags: excludeTags,
            raw: raw
        )
        let output = Output(
            rows: rows.map { row in
                Row(
                    id: row.id,
                    title: row.title,
                    summary: row.summary,
                    section: row.section,
                    path: verbose ? NoteAddress.relativeFile(forId: row.id) : nil,
                    tags: verbose
                        ? ((row.tagsCSV ?? "").isEmpty
                            ? []
                            : row.tagsCSV!.split(separator: ",").map(String.init))
                        : nil,
                    stale: verbose ? row.isStale : nil
                )
            },
            expanded: extra.map { note in
                Expanded(
                    id: note.id,
                    title: note.title,
                    summary: note.summary,
                    weight: note.weight,
                    path: verbose ? NoteAddress.relativeFile(forId: note.id) : nil
                )
            }
        )
        
        CommandOutput().render(output, json: format.json) { output -> [PlainBlock] in
            var blocks: [PlainBlock] = [
                verbose
                    ? .table(
                        output.rows.map { row in
                            [
                                row.id,
                                row.title + (row.stale == true ? "  [stale]" : ""),
                                (row.tags ?? []).joined(separator: ","),
                                row.section ?? "",
                                row.path ?? "",
                                row.summary ?? ""
                            ]
                        },
                        headers: ["id", "title", "tags", "section", "path", "summary"]
                    )
                    : .table(
                        output.rows.map { row in
                            [row.id, row.title, row.section ?? "", row.summary ?? ""]
                        },
                        headers: ["id", "title", "section", "summary"]
                    )
            ]
            
            if !output.expanded.isEmpty {
                blocks.append(.section("expanded (\(output.expanded.count))"))
                blocks.append(
                    verbose
                        ? .table(
                            output.expanded.map { note in
                                [
                                    note.id,
                                    String(format: "%.2f", note.weight),
                                    note.title,
                                    note.path ?? "",
                                    note.summary ?? ""
                                ]
                            },
                            headers: ["id", "weight", "title", "path", "summary"]
                        )
                        : .table(
                            output.expanded.map { note in
                                [
                                    note.id,
                                    String(format: "%.2f", note.weight),
                                    note.title,
                                    note.summary ?? ""
                                ]
                            },
                            headers: ["id", "weight", "title", "summary"]
                        )
                )
            }
            
            return blocks
        }
    }
    
    // MARK: - Private
}
