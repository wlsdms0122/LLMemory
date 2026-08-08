//
//  Consolidate.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct ConsolidateCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "consolidate",
        abstract: "Consolidation domain — mutating upkeep + read-only planning (LLM-free).",
        discussion: """
            The consolidation domain has two halves. The MUTATING ops are three
            independent upkeep passes, each its own concern and cadence — never
            bundled at the engine level (the caller composes them):

              · integrate (A) — non-destructive upkeep: events compaction,
                source verify, prune, integrity L1, term validation, enrich
                review, vector rebuild. Idempotent, safe to run often.
              · prune (B) — destructive decay: learned link weights decayed,
                links pruned below floor. One call = one subjective-time tick.
              · homeostasis (H) — deterministic meta-plasticity: consumes
                closed activity windows exactly once and may adjust ONE
                mutable read-path gene within bounds (see `genome list`).

            The READ-ONLY surfaces plan and inspect that upkeep (no writes):
            candidates (restructure/cleanup candidates the agent acts on) and
            report (axis + tag health).

            SEMANTIC ENRICHMENT LIFECYCLE (integrate)
                integrate drives the deterministic side of enrichment (LLM
                emits via capture; llmemory owns slots, validation, retrieval):
                  · retrieval terms — round-trip + IDF validation pass
                    (terms_activated / terms_rejected); terms stuck pending past
                    the age cutoff are finalized as rejected.
                  · assoc edges — the link decay/strengthen loop IS their
                    validator (decay lives in `prune`, not here).
                  · ensemble disagreement — assoc edges far apart in note_vectors
                    are quarantined with an enrich_review ripple flag; a pass also
                    resolves flags whose disagreement cleared (cosine recovered
                    or edge pruned), so the gauge tracks the live set.
                Observe runtime state with `query enrichment`.

            SEE ALSO
                consolidate integrate, consolidate prune
                consolidate candidates, consolidate report
                query enrichment, index vector, index verify terms
            """,
        subcommands: [
            ConsolidateIntegrate.self,
            ConsolidatePrune.self,
            ConsolidateHomeostasis.self,
            ConsolidateCandidates.self,
            ConsolidateReport.self
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct ConsolidateIntegrate: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "integrate",
        abstract: "(A) Non-destructive upkeep — no decay.",
        discussion: """
            LLM-free, idempotent. Safe to run frequently (e.g. hourly) and for
            recovery — never decays links.
            Default output is plain text; --json emits the typed summary.

            EXAMPLES
                llmemory consolidate integrate --home brain
                llmemory consolidate integrate --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        Session.configure(home: global.home)
        
        let result = try await Consolidate.integrate()
        
        emitConsolidateSummary(result.summary, json: format.json)
    }
    
    // MARK: - Private
}

struct ConsolidateHomeostasis: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "homeostasis",
        abstract: "(H) Deterministic meta-plasticity tick — adjust mutable genes from the activation trace.",
        discussion: """
            LLM 0. Consumes closed activity windows exactly once (watermark),
            accumulates waste evidence, and when the sample is large enough
            adjusts at most ONE mutable read-path gene by one step within its
            bounds — never past wild-type. Locked (write-path) genes are out of
            reach by construction; move those with the `set_gene` op, with a
            reason, when there is one.

            v1 rule: expansion landing — expand-surfaced notes that are never
            opened (`get`) in their window are dead weight; a persistently ~0
            landing rate narrows `related.expand_hops`, a healthy rate restores
            it toward wild-type.

            Safe at any call frequency: windows are consumed exactly once and
            evidence accumulates across calls until min_sample is reached.

            EXAMPLES
                llmemory consolidate homeostasis --home brain
                llmemory consolidate homeostasis --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        Session.configure(home: global.home)
        
        let result = try await Consolidate.homeostasis()
        
        emitConsolidateSummary(result, json: format.json)
    }
    
    // MARK: - Private
}

struct ConsolidatePrune: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "(B) Decay learned link weights, prune below floor.",
        discussion: """
            Destructive. One call is one subjective-time tick — the caller's
            cadence is the clock (this bot only runs when used, so invocation
            count, not wall time, is the right axis). Run sparingly (e.g. with
            the replay flow), not on every integrate pass.

            EXAMPLES
                llmemory consolidate prune --home brain
                llmemory consolidate prune --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        Session.configure(home: global.home)
        
        let result = try await Consolidate.prune()
        
        emitConsolidateSummary(result, json: format.json)
    }
    
    // MARK: - Private
}

struct ConsolidateReport: AsyncParsableCommand {
    struct AxisRow: Encodable {
        // MARK: - Property
        let axis: String
        let count: Int
        let description: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
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
            case axes
            case smallAxes = "small_axes"
            case largeAxes = "large_axes"
            case rareTags = "rare_tags"
            case unusedTags = "unused_tags"
        }
        
        // MARK: - Property
        let axes: [AxisRow]
        let smallAxes: [AxisRow]
        let largeAxes: [AxisRow]
        let rareTags: [TagRow]
        let unusedTags: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Axis + tag health report (plain text).",
        discussion: """
            Lists every axis with note count and description, marks SMALL
            (<=2) and LARGE (>=20) axes, surfaces rare tags (<=1 use), and
            shows unused vocab tags.

            EXAMPLES
                llmemory consolidate report --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        Session.configure(home: global.home)
        
        let (axisReport, tagReport) = try await Consolidate.report()
        let report = ReportOutput(
            axes: axisReport.all.map { entry in
                AxisRow(axis: entry.axis, count: entry.count, description: entry.description)
            },
            smallAxes: axisReport.small.map { entry in
                AxisRow(axis: entry.axis, count: entry.count, description: nil)
            },
            largeAxes: axisReport.large.map { entry in
                AxisRow(axis: entry.axis, count: entry.count, description: nil)
            },
            rareTags: tagReport.rare.map { entry in
                TagRow(tag: entry.tag, count: entry.count)
            },
            unusedTags: tagReport.unused
        )
        
        render(report, json: format.json) { report in
            var blocks: [PlainBlock] = [
                .section("axes (count asc)"),
                .table(
                    report.axes.map { row in
                        [row.axis, String(row.count), row.description ?? ""]
                    },
                    headers: ["axis", "count", "description"]
                )
            ]
            
            if !report.smallAxes.isEmpty {
                blocks.append(.section("small axes (<=2)"))
                blocks.append(
                    .table(
                        report.smallAxes.map { row in [row.axis, String(row.count)] },
                        headers: ["axis", "count"]
                    )
                )
            }
            
            if !report.largeAxes.isEmpty {
                blocks.append(.section("large axes (>=20)"))
                blocks.append(
                    .table(
                        report.largeAxes.map { row in [row.axis, String(row.count)] },
                        headers: ["axis", "count"]
                    )
                )
            }
            
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
            case id, axis, title, sections, reason
            case wordCount = "word_count"
            case sectionCount = "section_count"
            case tagCount = "tag_count"
        }
        
        // MARK: - Property
        let id, axis, title: String
        let reason: String
        let wordCount, sectionCount, tagCount: Int?
        let sections: [SectionSketch]?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct FlaggedItem: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, reason, axis, title, summary
            case createdAt = "created_at"
        }
        
        // MARK: - Property
        let id: String
        let reason: String?
        let axis, title: String
        let summary: String?
        let createdAt: Int?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct ClusterItem: Encodable {
        struct Member: Encodable {
            // MARK: - Property
            let id, axis, title: String
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
        let axes: [String]
        let members: [Member]
        let edges: [Edge]?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct MissingEdgeItem: Encodable {
        struct Member: Encodable {
            // MARK: - Property
            let id, axis, title: String
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
            let id, axis, title: String
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
        let validKinds = QueryFeature.candidateValidKinds + ["all", "retrieval", "structural"]
        
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
            kinds = QueryFeature.candidateValidKinds
            groupMode = true
        
        case "retrieval":
            kinds = QueryFeature.candidateRetrievalKinds
            groupMode = true
        
        case "structural":
            kinds = QueryFeature.candidateStructuralKinds
            groupMode = true
        
        default:
            kinds = [kind]
            groupMode = false
        }
        
        let batches = try await QueryFeature.candidates(home: global.home, kinds: kinds, limit: limit)
        let result: [String: KindOutput] = batches.mapValues { batch in
            mapBatch(batch, full: verbose)
        }
        
        if format.json {
            if groupMode {
                emit(result)
            } else if let batch = result[kind] {
                emit(batch)
            } else {
                emit([SplitItem]())
            }
            
            return
        }
        
        var blocks: [PlainBlock] = []
        
        for kind in kinds {
            guard let batch = result[kind] else { continue }
            
            blocks.append(.section("\(kind) (\(batch.count))"))
            blocks.append(itemTable(batch))
        }
        
        Plain.render(blocks)
    }
    
    // MARK: - Private
    private func itemTable(_ batch: KindOutput) -> PlainBlock {
        switch batch {
        case .split(let items):
            if items.contains(where: { item in item.wordCount != nil }) {
                return .table(
                    items.map { item in
                        [
                            item.axis,
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
                        "axis", "id", "words", "sections", "tags", "reason", "title", "sketch"
                    ]
                )
            }
            
            return .table(
                items.map { item in [item.axis, item.id, item.reason, item.title] },
                headers: ["axis", "id", "reason", "title"]
            )
        
        case .reconsolidate(let items), .ripple(let items):
            if items.contains(where: { item in item.createdAt != nil }) {
                return .table(
                    items.map { item in
                        [
                            item.axis,
                            item.id,
                            item.createdAt.map(dayString) ?? "-",
                            item.reason ?? "",
                            item.title,
                            item.summary ?? ""
                        ]
                    },
                    headers: ["axis", "id", "flagged", "reason", "title", "summary"]
                )
            }
            
            return .table(
                items.map { item in
                    [item.axis, item.id, item.reason ?? "", item.title, item.summary ?? ""]
                },
                headers: ["axis", "id", "reason", "title", "summary"]
            )
        
        case .clusters(let items):
            if items.contains(where: { item in item.edges != nil }) {
                return .table(
                    items.map { item in
                        [
                            String(item.size),
                            item.axes.joined(separator: ","),
                            item.members.map(\.id).joined(separator: ", "),
                            (item.edges ?? [])
                                .map { edge in "\(edge.a)↔\(edge.b)" }
                                .joined(separator: ", ")
                        ]
                    },
                    headers: ["size", "axes", "members", "edges"]
                )
            }
            
            return .table(
                items.map { item in
                    [
                        String(item.size),
                        item.axes.joined(separator: ","),
                        item.members.map(\.id).joined(separator: ", ")
                    ]
                },
                headers: ["size", "axes", "members"]
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
    
    private func mapBatch(_ batch: QueryFeature.CandidateBatch, full: Bool) -> KindOutput {
        switch batch {
        case .split(let items):
            return .split(
                items.map { candidate in
                    SplitItem(
                        id: candidate.id,
                        axis: candidate.axis,
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
                        axis: candidate.axis,
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
                        axes: cluster.axes,
                        members: cluster.members.map { member in
                            ClusterItem.Member(
                                id: member.id,
                                axis: member.axis,
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
                            axis: edge.a.axis,
                            title: edge.a.title,
                            summary: edge.a.summary
                        ),
                        b: .init(
                            id: edge.b.id,
                            axis: edge.b.axis,
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
                            axis: duplicate.a.axis,
                            title: duplicate.a.title,
                            summary: duplicate.a.summary
                        ),
                        b: .init(
                            id: duplicate.b.id,
                            axis: duplicate.b.axis,
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

private func emitConsolidateSummary<T: Encodable>(_ summary: T, json: Bool) {
    renderReflected(summary, json: json)
}
