//
//  QueryStats.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryStats: AsyncParsableCommand {
    struct NoteOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, title, summary, priority, stale
            case createdAt = "created_at"
            case editedAt = "edited_at"
            case ageDays = "age_days"
            case sinceEditDays = "since_edit_days"
            case sinceRetrievalDays = "since_retrieval_days"
            case hitCount = "hit_count"
            case wordCount = "word_count"
            case sectionCount = "section_count"
            case tagCount = "tag_count"
            case linkCount = "link_count"
        }
        
        // MARK: - Property
        let id, title: String
        let summary: String?
        let priority: String
        let createdAt, editedAt: Int
        let ageDays, sinceEditDays, sinceRetrievalDays: Int?
        let hitCount, wordCount, sectionCount: Int
        let stale: Bool
        let tagCount, linkCount: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct PrefixOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case total, stale, eager
            case avgWords = "avg_words"
            case maxWords = "max_words"
            case avgSections = "avg_sections"
            case totalHits = "total_hits"
        }
        
        // MARK: - Property
        let total, stale, eager: Int
        let avgWords: Double
        let maxWords: Int
        let avgSections: Double
        let totalHits: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct OverallOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case total, stale, tree
            case hitNonZero = "hit_non_zero"
            case hitZero = "hit_zero"
            case hitAvg = "hit_avg"
            case hitMax = "hit_max"
            case avgWords = "avg_words"
            case maxWords = "max_words"
            case avgSections = "avg_sections"
            case activation
        }
        
        // MARK: - Property
        let total, stale: Int
        let tree: [TreeRow]
        let hitNonZero, hitZero: Int
        let hitAvg: Double
        let hitMax: Int
        let avgWords: Double
        let maxWords: Int
        let avgSections: Double
        let activation: ActivationStats
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Note / prefix / overall counters and rates.",
        discussion: """
            Three modes determined by which option is set.

            MODES
                --id <note>     Per-note stats (age, hits, sections, tags, links).
                --prefix <p>    Aggregates over everything at or under that id.
                (neither)       Overall stats.

            EXAMPLES
                llmemory query stats --home brain
                llmemory query stats --id principles --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Per-note stats.")
    var id: String?
    
    @Option(name: .long, help: "Aggregates over everything at or under this id prefix.")
    var prefix: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        if let id {
            guard let stats = try await brain.query.noteStats(id: id) else {
                FileHandle.standardError.write("unknown id: \(id)\n".data(using: .utf8)!)
                
                throw ExitCode(1)
            }
            
            let output = NoteOutput(
                id: stats.id,
                title: stats.title,
                summary: stats.summary,
                priority: stats.priority,
                createdAt: stats.createdAt,
                editedAt: stats.editedAt,
                ageDays: stats.ageDays,
                sinceEditDays: stats.sinceEditDays,
                sinceRetrievalDays: stats.sinceRetrievalDays,
                hitCount: stats.hitCount,
                wordCount: stats.wordCount,
                sectionCount: stats.sectionCount,
                stale: stats.stale,
                tagCount: stats.tagCount,
                linkCount: stats.linkCount
            )
            
            CommandOutput().render(output, json: format.json) { output -> [PlainBlock] in
                let pairs: [(String, String)] = [
                    ("id", output.id),
                    ("title", output.title),
                    ("priority", output.priority),
                    ("hits", String(output.hitCount)),
                    ("words", String(output.wordCount)),
                    ("sections", String(output.sectionCount)),
                    ("tags", String(output.tagCount)),
                    ("links", String(output.linkCount)),
                    ("age_days", output.ageDays.map(String.init) ?? "-"),
                    ("since_edit_days", output.sinceEditDays.map(String.init) ?? "-"),
                    ("since_retrieval_days", output.sinceRetrievalDays.map(String.init) ?? "-"),
                    ("stale", output.stale ? "yes" : "no")
                ]
                
                return [.keyValue(pairs)]
            }
        } else if let prefix {
            let stats = try await brain.query.prefixStats(prefix: prefix)
            let output = PrefixOutput(
                total: stats.total,
                stale: stats.stale,
                eager: stats.eager,
                avgWords: stats.avgWords,
                maxWords: stats.maxWords,
                avgSections: stats.avgSections,
                totalHits: stats.totalHits
            )
            
            CommandOutput().render(output, json: format.json) { output -> [PlainBlock] in
                let pairs: [(String, String)] = [
                    ("total", String(output.total)),
                    ("stale", String(output.stale)),
                    ("eager", String(output.eager)),
                    ("avg_words", String(format: "%.0f", output.avgWords)),
                    ("max_words", String(output.maxWords)),
                    ("avg_sections", String(format: "%.1f", output.avgSections)),
                    ("total_hits", String(output.totalHits))
                ]
                
                return [.keyValue(pairs)]
            }
        } else {
            let stats = try await brain.query.overallStats()
            let output = OverallOutput(
                total: stats.total,
                stale: stats.stale,
                tree: stats.tree,
                hitNonZero: stats.hitNonZero,
                hitZero: stats.hitZero,
                hitAvg: stats.hitAvg,
                hitMax: stats.hitMax,
                avgWords: stats.avgWords,
                maxWords: stats.maxWords,
                avgSections: stats.avgSections,
                activation: stats.activation
            )
            
            CommandOutput().render(output, json: format.json) { output -> [PlainBlock] in
                let pairs: [(String, String)] = [
                    ("total", String(output.total)),
                    ("stale", String(output.stale)),
                    ("hit_non_zero", String(output.hitNonZero)),
                    ("hit_zero", String(output.hitZero)),
                    ("hit_avg", String(format: "%.2f", output.hitAvg)),
                    ("hit_max", String(output.hitMax)),
                    ("avg_words", String(format: "%.0f", output.avgWords)),
                    ("max_words", String(output.maxWords)),
                    ("avg_sections", String(format: "%.1f", output.avgSections))
                ]
                let activation = output.activation
                let activationPairs: [(String, String)] = [
                    ("windows", String(activation.windows)),
                    ("labeled_windows", String(activation.labeledWindows)),
                    ("surfaced", String(activation.surfaced)),
                    ("used", String(activation.used))
                ]
                
                return [
                    .keyValue(pairs),
                    .section("by prefix"),
                    .table(
                        output.tree.map { row in [row.prefix, String(row.notes)] },
                        headers: ["prefix", "notes"]
                    ),
                    .section("activation"),
                    .keyValue(activationPairs),
                    .table(
                        activation.byPrefix.map { entry in
                            [entry.prefix, String(entry.surfaced), String(entry.used)]
                        },
                        headers: ["prefix", "surfaced", "used"]
                    )
                ]
            }
        }
    }
    
    // MARK: - Private
}
