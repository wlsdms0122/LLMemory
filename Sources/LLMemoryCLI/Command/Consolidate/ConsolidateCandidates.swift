//
//  ConsolidateCandidates.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct ConsolidateCandidates: AsyncParsableCommand {
    struct SectionSketch: Encodable {
        enum CodingKeys: String, CodingKey {
            case path, title
            case wordCount = "word_count"
        }
        
        // MARK: - Property
        let path, title: String
        let wordCount: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct SplitItem: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, title, sections, reason
            case wordCount = "word_count"
            case sectionCount = "section_count"
            case tagCount = "tag_count"
        }
        
        // MARK: - Property
        let id, title: String
        let reason: String
        let wordCount, sectionCount, tagCount: Int?
        let sections: [SectionSketch]?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct FlaggedItem: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, reason, title, summary
            case createdAt = "created_at"
        }
        
        // MARK: - Property
        let id: String
        let reason: String?
        let title: String
        let summary: String?
        let createdAt: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct ClusterItem: Encodable {
        struct Member: Encodable {
            // MARK: - Property
            let id, title: String
            let summary: String?
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        struct Edge: Encodable {
            // MARK: - Property
            let a, b: String
            let fts, entity, link: Double
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        let size: Int
        let members: [Member]
        let edges: [Edge]?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct MissingEdgeItem: Encodable {
        struct Member: Encodable {
            // MARK: - Property
            let id, title: String
            let summary: String?
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        let a: Member
        let b: Member
        let source: String
        let score: Double
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct NearDuplicateItem: Encodable {
        struct Member: Encodable {
            // MARK: - Property
            let id, title: String
            let summary: String?
            
            // MARK: - Initializer
            // MARK: - Public
            // MARK: - Private
        }
        
        // MARK: - Property
        let a: Member
        let b: Member
        let jaccard, containment: Double
        let fts, entity, link: Double?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    enum KindOutput: Encodable {
        case split([SplitItem])
        case reconsolidate([FlaggedItem])
        case ripple([FlaggedItem])
        case clusters([ClusterItem])
        case missingEdge([MissingEdgeItem])
        case nearDuplicate([NearDuplicateItem])
        
        var count: Int {
            switch self {
            case .split(let items):
                return items.count
            
            case .reconsolidate(let items):
                return items.count
            
            case .ripple(let items):
                return items.count
            
            case .clusters(let items):
                return items.count
            
            case .missingEdge(let items):
                return items.count
            
            case .nearDuplicate(let items):
                return items.count
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            
            switch self {
            case .split(let items):
                try container.encode(items)
            
            case .reconsolidate(let items):
                try container.encode(items)
            
            case .ripple(let items):
                try container.encode(items)
            
            case .clusters(let items):
                try container.encode(items)
            
            case .missingEdge(let items):
                try container.encode(items)
            
            case .nearDuplicate(let items):
                try container.encode(items)
            }
        }
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "candidates",
        abstract: "Surface restructure/cleanup candidates by kind.",
        discussion: """
            Feeds the upkeep flows: maintain reads `missing_edge` to enrich
            (assoc/terms), the consolidator reads the rest to plan structural
            mutations (merge/split/archive). LLM-free — the agent decides.

            KINDS
                retrieval     clusters, missing_edge, near_duplicate
                structural    split, reconsolidate, ripple, enrich_review
                aggregates    all, retrieval, structural

            EXAMPLES
                llmemory consolidate candidates --kind split --home brain
                llmemory consolidate candidates --kind all --limit 30 --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Candidate kind (see KINDS).")
    var kind: String
    
    @Option(name: .long, help: "Max rows per kind (default 20).")
    var limit: Int = 20
    
    @Flag(name: .long, help: "Raise the data level: adds per-item diagnostics (word/section counts, sketches, timestamps, cluster edges, score components) — same fields in plain and --json.")
    var verbose: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let validKinds = brain.query.candidateValidKinds + ["all", "retrieval", "structural"]
        
        if !Set(validKinds).contains(kind) {
            let choices = validKinds.map { choice in "'\(choice)'" }.joined(separator: ", ")
            
            throw ValidationError(
                "argument --kind: invalid choice: '\(kind)' (choose from \(choices))"
            )
        }
        
        let kinds: [String]
        let groupMode: Bool
        
        switch kind {
        case "all":
            kinds = brain.query.candidateValidKinds
            groupMode = true
        
        case "retrieval":
            kinds = brain.query.candidateRetrievalKinds
            groupMode = true
        
        case "structural":
            kinds = brain.query.candidateStructuralKinds
            groupMode = true
        
        default:
            kinds = [kind]
            groupMode = false
        }
        
        let batches = try await brain.query.candidates(kinds: kinds, limit: limit)
        let result: [String: KindOutput] = batches.mapValues { batch in
            mapBatch(batch, full: verbose)
        }
        
        if format.json {
            if groupMode {
                JSONOutput().emit(result)
            } else if let batch = result[kind] {
                JSONOutput().emit(batch)
            } else {
                JSONOutput().emit([SplitItem]())
            }
            
            return
        }
        
        var blocks: [PlainBlock] = []
        
        for kind in kinds {
            guard let batch = result[kind] else { continue }
            
            blocks.append(.section("\(kind) (\(batch.count))"))
            blocks.append(itemTable(batch))
        }
        
        PlainOutput().render(blocks)
    }
    
    // MARK: - Private
    private func itemTable(_ batch: KindOutput) -> PlainBlock {
        switch batch {
        case .split(let items):
            if items.contains(where: { item in item.wordCount != nil }) {
                return .table(
                    items.map { item in
                        [
                            item.id,
                            String(item.wordCount ?? 0),
                            String(item.sectionCount ?? 0),
                            String(item.tagCount ?? 0),
                            item.reason,
                            item.title,
                            (item.sections ?? [])
                                .map { section in "\(section.path)(\(section.wordCount))" }
                                .joined(separator: " | ")
                        ]
                    },
                    headers: [
                        "id", "words", "sections", "tags", "reason", "title", "sketch"
                    ]
                )
            }
            
            return .table(
                items.map { item in [item.id, item.reason, item.title] },
                headers: ["id", "reason", "title"]
            )
        
        case .reconsolidate(let items), .ripple(let items):
            if items.contains(where: { item in item.createdAt != nil }) {
                return .table(
                    items.map { item in
                        [
                            item.id,
                            item.createdAt.map { epoch in DayStamp().dayString(epoch) } ?? "-",
                            item.reason ?? "",
                            item.title,
                            item.summary ?? ""
                        ]
                    },
                    headers: ["id", "flagged", "reason", "title", "summary"]
                )
            }
            
            return .table(
                items.map { item in
                    [item.id, item.reason ?? "", item.title, item.summary ?? ""]
                },
                headers: ["id", "reason", "title", "summary"]
            )
        
        case .clusters(let items):
            if items.contains(where: { item in item.edges != nil }) {
                return .table(
                    items.map { item in
                        [
                            String(item.size),
                            item.members.map(\.id).joined(separator: ", "),
                            (item.edges ?? [])
                                .map { edge in "\(edge.a)↔\(edge.b)" }
                                .joined(separator: ", ")
                        ]
                    },
                    headers: ["size", "members", "edges"]
                )
            }
            
            return .table(
                items.map { item in
                    [
                        String(item.size),
                        item.members.map(\.id).joined(separator: ", ")
                    ]
                },
                headers: ["size", "members"]
            )
        
        case .missingEdge(let items):
            return .table(
                items.map { item in
                    [item.a.id, item.b.id, item.source, String(format: "%.2f", item.score)]
                },
                headers: ["a", "b", "source", "score"]
            )
        
        case .nearDuplicate(let items):
            if items.contains(where: { item in item.fts != nil }) {
                return .table(
                    items.map { item in
                        [
                            item.a.id,
                            item.b.id,
                            String(format: "%.2f", item.jaccard),
                            String(format: "%.2f", item.containment),
                            String(format: "%.2f", item.fts ?? 0),
                            String(format: "%.2f", item.entity ?? 0),
                            String(format: "%.2f", item.link ?? 0)
                        ]
                    },
                    headers: ["a", "b", "jaccard", "containment", "fts", "entity", "link"]
                )
            }
            
            return .table(
                items.map { item in
                    [
                        item.a.id,
                        item.b.id,
                        String(format: "%.2f", item.jaccard),
                        String(format: "%.2f", item.containment)
                    ]
                },
                headers: ["a", "b", "jaccard", "containment"]
            )
        }
    }
    
    private func mapBatch(_ batch: CandidateBatch, full: Bool) -> KindOutput {
        switch batch {
        case .split(let items):
            return .split(
                items.map { candidate in
                    SplitItem(
                        id: candidate.id,
                        title: candidate.title,
                        reason: candidate.reason,
                        wordCount: full ? candidate.wordCount : nil,
                        sectionCount: full ? candidate.sectionCount : nil,
                        tagCount: full ? candidate.tagCount : nil,
                        sections: full
                            ? candidate.sections.map { section in
                                SectionSketch(
                                    path: section.path,
                                    title: section.title,
                                    wordCount: section.wordCount
                                )
                            }
                            : nil
                    )
                }
            )
        
        case .flagged(let items):
            return .reconsolidate(
                items.map { candidate in
                    FlaggedItem(
                        id: candidate.id,
                        reason: candidate.reason,
                        title: candidate.title,
                        summary: candidate.summary,
                        createdAt: full ? candidate.createdAt : nil
                    )
                }
            )
        
        case .clusters(let items):
            return .clusters(
                items.map { cluster in
                    ClusterItem(
                        size: cluster.size,
                        members: cluster.members.map { member in
                            ClusterItem.Member(
                                id: member.id,
                                title: member.title,
                                summary: member.summary
                            )
                        },
                        edges: full
                            ? cluster.edges.map { edge in
                                ClusterItem.Edge(
                                    a: edge.a,
                                    b: edge.b,
                                    fts: edge.fts,
                                    entity: edge.entity,
                                    link: edge.link
                                )
                            }
                            : nil
                    )
                }
            )
        
        case .missingEdge(let items):
            return .missingEdge(
                items.map { edge in
                    MissingEdgeItem(
                        a: .init(
                            id: edge.a.id,
                            title: edge.a.title,
                            summary: edge.a.summary
                        ),
                        b: .init(
                            id: edge.b.id,
                            title: edge.b.title,
                            summary: edge.b.summary
                        ),
                        source: edge.source,
                        score: edge.score
                    )
                }
            )
        
        case .nearDuplicate(let items):
            return .nearDuplicate(
                items.map { duplicate in
                    NearDuplicateItem(
                        a: .init(
                            id: duplicate.a.id,
                            title: duplicate.a.title,
                            summary: duplicate.a.summary
                        ),
                        b: .init(
                            id: duplicate.b.id,
                            title: duplicate.b.title,
                            summary: duplicate.b.summary
                        ),
                        jaccard: duplicate.jaccard,
                        containment: duplicate.containment,
                        fts: full ? duplicate.fts : nil,
                        entity: full ? duplicate.entity : nil,
                        link: full ? duplicate.link : nil
                    )
                }
            )
        }
    }
}
