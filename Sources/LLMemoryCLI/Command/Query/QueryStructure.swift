//
//  QueryStructure.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryStructure: AsyncParsableCommand {
    struct KindRow: Encodable {
        // MARK: - Property
        let kind: String
        let count: Int
        let min, avg, max: Double
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct DegreeRow: Encodable {
        // MARK: - Property
        let id, title: String
        let degree: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct LinksReport: Encodable {
        enum CodingKeys: String, CodingKey {
            case byKind = "by_kind"
            case weightBuckets = "weight_buckets"
            case topDegree = "top_degree"
        }
        
        // MARK: - Property
        let byKind: [KindRow]
        let weightBuckets: [String: Int]
        let topDegree: [DegreeRow]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Output: Encodable {
        enum CodingKeys: String, CodingKey {
            case tree, links
            case prefixStats = "prefix_stats"
        }
        
        // MARK: - Property
        let tree: [TreeRow]
        let links: LinksReport
        let prefixStats: QueryStats.PrefixOutput?
        
        // MARK: - Initializer
        // MARK: - Public
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(tree, forKey: .tree)
            try container.encode(links, forKey: .links)
            
            if let prefixStats { try container.encode(prefixStats, forKey: .prefixStats) }
        }
        
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "structure",
        abstract: "Memory topology — id hierarchy, link distribution, top-degree notes.",
        discussion: """
            Useful before running consolidation. Pass --prefix for the stats of
            one branch of the address space.

            EXAMPLES
                llmemory query structure --home brain
                llmemory query structure --prefix flow --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Add stats for everything at or under this id prefix.")
    var prefix: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let structure = try await brain.query.structure(prefix: prefix)
        let distribution = structure.distribution
        let stats: QueryStats.PrefixOutput? = structure.prefixStats.map { stats in
            QueryStats.PrefixOutput(
                total: stats.total,
                stale: stats.stale,
                eager: stats.eager,
                avgWords: stats.avgWords,
                maxWords: stats.maxWords,
                avgSections: stats.avgSections,
                totalHits: stats.totalHits
            )
        }
        let output = Output(
            tree: structure.tree,
            links: LinksReport(
                byKind: distribution.byKind.map { entry in
                    KindRow(
                        kind: entry.kind,
                        count: entry.count,
                        min: entry.min,
                        avg: entry.avg,
                        max: entry.max
                    )
                },
                weightBuckets: distribution.weightBuckets,
                topDegree: distribution.topDegree.map { entry in
                    DegreeRow(
                        id: entry.id,
                        title: entry.title,
                        degree: entry.degree
                    )
                }
            ),
            prefixStats: stats
        )
        
        CommandOutput().render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .section("tree (\(output.tree.count))"),
                .table(
                    output.tree.map { row in [row.prefix, String(row.notes)] },
                    headers: ["prefix", "notes"]
                ),
                .section("links by kind"),
                .table(
                    output.links.byKind.map { row in
                        [
                            row.kind,
                            String(row.count),
                            String(format: "%.2f", row.min),
                            String(format: "%.2f", row.avg),
                            String(format: "%.2f", row.max)
                        ]
                    },
                    headers: ["kind", "count", "min", "avg", "max"]
                )
            ]
            
            if !output.links.topDegree.isEmpty {
                blocks.append(.section("top-degree notes"))
                blocks.append(
                    .table(
                        output.links.topDegree.map { row in
                            [row.id, String(row.degree), row.title]
                        },
                        headers: ["id", "degree", "title"]
                    )
                )
            }
            
            if let stats = output.prefixStats {
                blocks.append(.section("prefix stats"))
                blocks.append(
                    .keyValue([
                        ("total", String(stats.total)),
                        ("stale", String(stats.stale)),
                        ("eager", String(stats.eager)),
                        ("avg_words", String(format: "%.0f", stats.avgWords)),
                        ("max_words", String(stats.maxWords)),
                        ("avg_sections", String(format: "%.1f", stats.avgSections)),
                        ("total_hits", String(stats.totalHits))
                    ])
                )
            }
            
            return blocks
        }
    }
    
    // MARK: - Private
}
