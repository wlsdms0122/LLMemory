//
//  QueryGet.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryGet: AsyncParsableCommand {
    struct Stats: Encodable {
        enum CodingKeys: String, CodingKey {
            case priority
            case hitCount = "hit_count"
            case createdAt = "created_at"
            case editedAt = "edited_at"
        }
        
        // MARK: - Property
        let hitCount: Int
        let priority: String
        let createdAt: Int?
        let editedAt: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Output: Encodable {
        // MARK: - Property
        let id: String
        let path: String
        let frontmatter: NoteFrontmatter
        let body: String
        var sections: [String]? = nil
        let stats: Stats
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct TocRow: Encodable {
        // MARK: - Property
        let section: String
        let words: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct TocOutput: Encodable {
        // MARK: - Property
        let id: String
        let path: String
        let toc: [TocRow]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct BudgetOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, path, frontmatter, body, truncated, stats
            case shownWords = "shown_words"
            case totalWords = "total_words"
            case shownSections = "shown_sections"
            case omittedSections = "omitted_sections"
            case truncatedWithin = "truncated_within"
        }
        
        // MARK: - Property
        let id: String
        let path: String
        let frontmatter: NoteFrontmatter
        let body: String
        let truncated: Bool
        let shownWords: Int
        let totalWords: Int
        let shownSections: [TocRow]
        let omittedSections: [TocRow]
        let truncatedWithin: String?
        let stats: Stats
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "get",
        abstract: "Fetch one or more notes by id — frontmatter, body, stats. Section-granular via --section/--toc.",
        discussion: """
            The sanctioned way to read a note body — do not read cortex/
            files directly.

            Accepts multiple ids; notes are emitted in the order given.
            Unknown ids are reported on stderr and cause a non-zero exit,
            but the known notes are still emitted.

            SECTION-GRANULAR READS (single id only)
                --toc          list the note's section paths + word counts
                               without printing the body. The paths are what
                               --section (and ops like patch_section) accept.
                --section P    print only that section's subtree (heading
                               included). Repeatable. Path syntax is the ops
                               one — "## A > ### B"; unknown or ambiguous
                               paths fail loud.
                --budget W     word budget: print the preamble + whole top-level
                               sections until W words, then STOP at a section
                               boundary. The cut is never silent — a trailing
                               marker names every omitted section (with word
                               counts) and the exact command to read it. Never
                               cuts mid-section; a heading-free body ships whole.

            EXAMPLES
                llmemory query get principles --home brain
                llmemory query get identity principles tone --home brain
                llmemory query get skill-forge-send --toc --home brain
                llmemory query get skill-forge-send --section '## GitHub (`service=github`)' --home brain
                llmemory query get code-audit-llmemory-history --budget 800 --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Argument(help: "Note ids — an id is its address, so `a.b.c` is cortex/a/b/c.md.")
    var ids: [String]
    
    @Option(name: .long, help: "Section path to read (repeatable; single id only).")
    var section: [String] = []
    
    @Flag(name: .long, help: "List section paths + word counts instead of the body (single id only).")
    var toc: Bool = false
    
    @Option(name: .long, help: "Word budget — print whole top-level sections up to this many words, then stop with an explicit omitted-sections marker (single id only).")
    var budget: Int? = nil
    
    @Flag(name: .long, help: "Raise the data level: adds created/edited timestamps — same fields in plain and --json.")
    var verbose: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func validate() throws {
        if ids.isEmpty { throw ValidationError("at least one note id required") }
        
        if (toc || !section.isEmpty || budget != nil) && ids.count != 1 {
            throw ValidationError("--section/--toc/--budget address one note — pass a single id")
        }
        
        if [toc, !section.isEmpty, budget != nil].filter({ flag in flag }).count > 1 {
            throw ValidationError("--toc, --section and --budget are mutually exclusive")
        }
        
        if let budget, budget < 1 {
            throw ValidationError("--budget must be a positive word count")
        }
    }
    
    func run() async throws {
        let brain = Brain(home: global.home)
        
        if toc {
            try await runToc()
            
            return
        }
        
        if !section.isEmpty {
            try await runSections()
            
            return
        }
        
        if let budget {
            try await runBudget(budget)
            
            return
        }
        
        let (found, missing) = try await brain.query.get(
            ids: ids,
            cliSessionId: global.sessionId
        )
        let outputs: [Output] = found.map { note in
            Output(
                id: note.id,
                path: note.path,
                frontmatter: note.frontmatter,
                body: note.body,
                stats: Stats(
                    hitCount: note.hitCount,
                    priority: note.priority,
                    createdAt: verbose ? note.createdAt : nil,
                    editedAt: verbose ? note.editedAt : nil
                )
            )
        }
        
        for id in missing {
            FileHandle.standardError.write("unknown id: \(id)\n".data(using: .utf8)!)
        }
        
        CommandOutput().render(outputs, json: format.json) { outputs in
            var blocks: [PlainBlock] = []
            
            for (index, output) in outputs.enumerated() {
                if index > 0 { blocks.append(.blank) }
                
                blocks.append(.keyValue(headerPairs(output)))
                blocks.append(.blank)
                blocks.append(.text(output.body))
            }
            
            return blocks
        }
        
        if !missing.isEmpty { throw ExitCode(1) }
    }
    
    // MARK: - Private
    private func runSections() async throws {
        let brain = Brain(home: global.home)
        
        let (note, slices) = try await brain.query.getSections(
            id: ids[0],
            sections: section,
            cliSessionId: global.sessionId
        )
        let output = Output(
            id: note.id,
            path: note.path,
            frontmatter: note.frontmatter,
            body: slices.map { slice in slice.text }.joined(separator: "\n\n"),
            sections: slices.map { slice in slice.path },
            stats: Stats(
                hitCount: note.hitCount,
                priority: note.priority,
                createdAt: verbose ? note.createdAt : nil,
                editedAt: verbose ? note.editedAt : nil
            )
        )
        
        CommandOutput().render([output], json: format.json) { outputs in
            outputs.flatMap { output in
                [.keyValue(headerPairs(output)), .blank, .text(output.body)]
            }
        }
    }
    
    private func runBudget(_ budget: Int) async throws {
        let brain = Brain(home: global.home)
        
        let (note, cut) = try await brain.query.getBudget(
            id: ids[0],
            budget: budget,
            cliSessionId: global.sessionId
        )
        let output = BudgetOutput(
            id: note.id,
            path: note.path,
            frontmatter: note.frontmatter,
            body: cut.shown,
            truncated: cut.truncated,
            shownWords: cut.shownWords,
            totalWords: cut.totalWords,
            shownSections: cut.shownSections.map { entry in
                TocRow(section: entry.path, words: entry.words)
            },
            omittedSections: cut.omitted.map { entry in
                TocRow(section: entry.path, words: entry.words)
            },
            truncatedWithin: cut.truncatedWithin,
            stats: Stats(
                hitCount: note.hitCount,
                priority: note.priority,
                createdAt: verbose ? note.createdAt : nil,
                editedAt: verbose ? note.editedAt : nil
            )
        )
        
        CommandOutput().render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .keyValue(
                    headerPairs(
                        Output(
                            id: output.id,
                            path: output.path,
                            frontmatter: output.frontmatter,
                            body: "",
                            stats: output.stats
                        )
                    )
                ),
                .blank,
                .text(output.body)
            ]
            
            if output.truncated {
                blocks.append(.blank)
                
                if let region = output.truncatedWithin {
                    blocks.append(
                        .text("——— 잘림: `\(region)` 안(줄 경계)에서 예산 도달 · \(output.shownWords)/\(output.totalWords) words 출력 ———")
                    )
                } else {
                    blocks.append(
                        .text("——— 잘림: \(output.shownSections.count)/\(output.shownSections.count + output.omittedSections.count) 섹션 · \(output.shownWords)/\(output.totalWords) words 출력 ———")
                    )
                }
                
                if !output.omittedSections.isEmpty {
                    let preview = output.omittedSections.prefix(10)
                        .map { entry in "  \(entry.section) (\(entry.words)w)" }
                    var listing = preview.joined(separator: "\n")
                    
                    if output.omittedSections.count > 10 {
                        listing += "\n  … +\(output.omittedSections.count - 10) 섹션 (전체 목록: --toc)"
                    }
                    
                    blocks.append(
                        .text("생략된 섹션 (\(output.omittedSections.count)):\n" + listing)
                    )
                }
                
                var hops: [String] = []
                
                if let region = output.truncatedWithin, region != "(preamble)" {
                    hops.append(
                        "잘린 영역 전체: llmemory query get \(output.id) --section '\(region)' --home \(global.home)"
                    )
                }
                
                if let first = output.omittedSections.first?.section {
                    hops.append(
                        "이어 읽기: llmemory query get \(output.id) --section '\(first)' --home \(global.home)"
                    )
                }
                
                hops.append("구조 훑기: llmemory query get \(output.id) --toc --home \(global.home)")
                hops.append("전문: llmemory query get \(output.id) --home \(global.home)")
                blocks.append(.text(hops.joined(separator: "\n")))
            }
            
            return blocks
        }
    }
    
    private func runToc() async throws {
        let brain = Brain(home: global.home)
        
        let (note, entries) = try await brain.query.toc(id: ids[0], cliSessionId: global.sessionId)
        let output = TocOutput(
            id: note.id,
            path: note.path,
            toc: entries.map { entry in TocRow(section: entry.path, words: entry.words) }
        )
        
        CommandOutput().render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .keyValue([("id", output.id), ("path", output.path)]),
                .blank
            ]
            
            if output.toc.isEmpty {
                blocks.append(.text("(no sections)"))
            } else {
                blocks.append(
                    .table(
                        output.toc.map { row in [row.section, String(row.words)] },
                        headers: ["section", "words"]
                    )
                )
            }
            
            return blocks
        }
    }
    
    private func headerPairs(_ output: Output) -> [(String, String)] {
        var pairs: [(String, String)] = [
            ("id", output.id),
            ("path", output.path),
            ("priority", output.stats.priority),
            ("hits", String(output.stats.hitCount))
        ]
        
        if let createdAt = output.stats.createdAt {
            pairs.append(("created", DayStamp().dayString(createdAt)))
        }
        
        if let editedAt = output.stats.editedAt {
            pairs.append(("edited", DayStamp().dayString(editedAt)))
        }
        
        if let sections = output.sections {
            pairs.append(("sections", sections.joined(separator: " | ")))
        }
        
        return pairs
    }
}
