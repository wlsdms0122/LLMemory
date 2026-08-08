//
//  Query.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/7/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryCommand: ParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Read-only queries — search, fetch, structure, stats.",
        discussion: """
            All queries are LLM-free (algorithmic). For free-form text input,
            prefer `related` — it returns a rich snapshot suitable for capture
            and retrieval agents.

            SEE ALSO
                query related, query search, query get
            """,
        subcommands: [
            QueryRelated.self, QuerySearch.self, QueryGet.self, QueryMeta.self,
            QueryEntity.self, QueryStructure.self, QueryNeighbors.self,
            QueryStats.self, QueryList.self, QueryAxes.self,
            QueryHistory.self, QueryLint.self, QueryEnrichment.self,
            QueryTemplate.self
        ]
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}

struct QueryTemplate: AsyncParsableCommand {
    struct Output: Encodable {
        // MARK: - Property
        let id: String
        let axis: String
        let path: String
        let frame: [Template.FrameNode]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "template",
        abstract: "Parse a template note's heading frame + per-section guidance.",
        discussion: """
            A *document* note (frontmatter `template: <id>`) must keep this heading
            frame; ops apply rejects any mutation that breaks it. This command shows
            the frame the bot fills in — each node carries the guidance prose authored
            under that heading, so the author knows what each section is for.

            Every declared heading is required: it must be present, under its parent,
            in order (a section may be empty — content is free). No section outside the
            frame is allowed at a frame level. Headings *deeper* than a frame leaf, and
            all section content, are free. Heading matching is normalized
            (NFC, lowercase, leading numbering/bullets stripped).

            EXAMPLES
                llmemory query template tpl-tech-spec --home brain
                llmemory query template tpl-tech-spec --json --home brain
        """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Argument(help: "Template note id.")
    var id: String
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let (note, frame) = try await brain.query.template(id: id)
        let output = Output(id: note.id, axis: note.axis, path: note.path, frame: frame)
        
        render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .keyValue([("id", output.id), ("axis", output.axis), ("path", output.path)]),
                .blank
            ]
            
            if output.frame.isEmpty {
                blocks.append(.text("(no frame — template body has no headings)"))
                
                return blocks
            }
            
            var lines: [String] = []
            
            func walk(_ nodes: [Template.FrameNode]) {
                for node in nodes {
                    lines.append(String(repeating: "#", count: node.level) + " " + node.title)
                    
                    if !node.guide.isEmpty {
                        for line in node.guide.split(
                            separator: "\n",
                            omittingEmptySubsequences: false
                        ) {
                            lines.append("    " + line)
                        }
                    }
                    
                    walk(node.children)
                }
            }
            
            walk(output.frame)
            blocks.append(.text(lines.joined(separator: "\n")))
            
            return blocks
        }
    }
    
    // MARK: - Private
}

struct QueryAxes: AsyncParsableCommand {
    struct AxisRow: Encodable {
        // MARK: - Property
        let axis: String
        let count: Int
        let description: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "axes",
        abstract: "List every axis with note count (read of derived state).",
        discussion: """
            Axes are dynamic — capture can create new ones and rename_axis
            can rename any of them. Use to see what's actually in use vs.
            defined.

            EXAMPLES
                llmemory query axes --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let axes = try await brain.query.listAxes()
        let rows = axes.map { entry in
            AxisRow(axis: entry.axis, count: entry.count, description: entry.description)
        }
        
        render(rows, json: format.json) { rows in
            [
                .table(
                    rows.map { row in [row.axis, String(row.count), row.description ?? ""] },
                    headers: ["axis", "count", "description"]
                )
            ]
        }
    }
    
    // MARK: - Private
}

struct QueryEnrichment: AsyncParsableCommand {
    struct TermCount: Encodable {
        // MARK: - Property
        let kind, status: String
        let count: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct ProvenanceRow: Encodable {
        enum CodingKeys: String, CodingKey {
            case provenance, alarm
            case assocEdges = "assoc_edges"
            case disagreeEdges = "disagree_edges"
            case disagreeRate = "disagree_rate"
        }
        
        // MARK: - Property
        let provenance: String
        let assocEdges: Int
        let disagreeEdges: Int
        let disagreeRate: Double
        let alarm: Bool
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Output: Encodable {
        enum CodingKeys: String, CodingKey {
            case provenance
            case retrievalTerms = "retrieval_terms"
            case assocTotal = "assoc_total"
            case assocActive = "assoc_active"
            case assocDormant = "assoc_dormant"
            case vectorsBuiltAt = "vectors_built_at"
            case vectorsDim = "vectors_dim"
            case noteCount = "note_count"
            case vectorCount = "vector_count"
            case vectorCoverage = "vector_coverage"
            case reviewFlagged = "review_flagged"
        }
        
        // MARK: - Property
        let retrievalTerms: [TermCount]
        let assocTotal: Int
        let assocActive: Int
        let assocDormant: Int
        let vectorsBuiltAt: Int?
        let vectorsDim: Int?
        let noteCount: Int
        let vectorCount: Int
        let vectorCoverage: Double
        let provenance: [ProvenanceRow]
        let reviewFlagged: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "enrichment",
        abstract: "Observe the semantic-enrichment layer's runtime state.",
        discussion: """
            Makes the enrichment design observable, not just declared — so a
            port to another system can verify it is alive at a glance.

            REPORTS
                retrieval terms   alias/cue counts by status. pending = awaiting
                                  validation; active = passed round-trip + IDF
                                  and indexed into notes_fts.enrich; rejected =
                                  filtered (reason in note_retrieval_terms).
                assoc edges       LLM-proposed semantic edges: total, active
                                  (strengthened past the 0.5 traversal floor by
                                  co-retrieval), dormant (still below it; decay
                                  will prune if never used).
                vectors           build time, dim, and coverage (notes with a
                                  note_vectors row ÷ total notes).
                provenance        per-producer assoc-edge disagreement rate
                                  (share whose two notes are far apart in vector
                                  space). A rate above enrich.model_alarm_rate
                                  flags a possibly-noisy model — catches
                                  regressions when the capture model changes.

            EXAMPLES
                llmemory query enrichment --home brain
                llmemory query enrichment --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let status = try await brain.query.enrichment()
        let output = Output(
            retrievalTerms: status.termCounts.map { term in
                TermCount(kind: term.kind, status: term.status, count: term.count)
            },
            assocTotal: status.assocTotal,
            assocActive: status.assocActive,
            assocDormant: status.assocDormant,
            vectorsBuiltAt: status.vectorsBuiltAt,
            vectorsDim: status.vectorsDim,
            noteCount: status.noteCount,
            vectorCount: status.vectorCount,
            vectorCoverage: (status.vectorCoverage * 1000).rounded() / 1000,
            provenance: status.provenanceStats.map { stat in
                ProvenanceRow(
                    provenance: stat.provenance,
                    assocEdges: stat.assocEdges,
                    disagreeEdges: stat.disagreeEdges,
                    disagreeRate: (stat.disagreeRate * 1000).rounded() / 1000,
                    alarm: stat.alarm
                )
            },
            reviewFlagged: status.reviewFlagged
        )
        
        render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [.section("retrieval terms")]
            
            blocks.append(
                .table(
                    output.retrievalTerms.map { term in
                        [term.kind, term.status, String(term.count)]
                    },
                    headers: ["kind", "status", "count"]
                )
            )
            blocks.append(.section("assoc edges"))
            blocks.append(
                .keyValue([
                    ("total", String(output.assocTotal)),
                    ("active (>= floor)", String(output.assocActive)),
                    ("dormant (< floor)", String(output.assocDormant))
                ])
            )
            blocks.append(.section("vectors"))
            blocks.append(
                .keyValue([
                    ("built_at", output.vectorsBuiltAt.map(String.init) ?? "(never)"),
                    ("dim", output.vectorsDim.map(String.init) ?? "-"),
                    (
                        "coverage",
                        "\(output.vectorCount)/\(output.noteCount) (\(String(format: "%.0f%%", output.vectorCoverage * 100)))"
                    )
                ])
            )
            blocks.append(.section("provenance disagreement"))
            blocks.append(
                .table(
                    output.provenance.map { row in
                        [
                            row.provenance,
                            String(row.assocEdges),
                            String(row.disagreeEdges),
                            String(format: "%.2f", row.disagreeRate),
                            row.alarm ? "ALARM" : ""
                        ]
                    },
                    headers: ["provenance", "edges", "disagree", "rate", "flag"]
                )
            )
            blocks.append(.section("review queue"))
            blocks.append(
                .text("  enrich_review flagged (unresolved): \(output.reviewFlagged)")
            )
            
            return blocks
        }
    }
    
    // MARK: - Private
}

struct QueryRelated: AsyncParsableCommand {
    struct VectorLinkedRow: Encodable {
        // MARK: - Property
        let id, axis, title: String
        let summary: String?
        let cosine: Double
        let path: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct TagCount: Encodable {
        // MARK: - Property
        let tag: String
        let count: Int
        
        // MARK: - Initializer
        // MARK: - Public
        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            
            try container.encode(tag)
            try container.encode(count)
        }
        
        // MARK: - Private
    }
    
    struct CooccurRow: Encodable {
        // MARK: - Property
        let a, b: String
        let count: Int
        
        // MARK: - Initializer
        // MARK: - Public
        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            
            try container.encode(a)
            try container.encode(b)
            try container.encode(count)
        }
        
        // MARK: - Private
    }
    
    struct AxisRow: Encodable {
        enum CodingKeys: String, CodingKey {
            case axis, count, description
            case topTags = "top_tags"
        }
        
        // MARK: - Property
        let axis: String
        let count: Int
        let description: String?
        let topTags: [String]
        
        // MARK: - Initializer
        // MARK: - Public
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(axis, forKey: .axis)
            try container.encode(count, forKey: .count)
            try container.encode(description, forKey: .description)
            try container.encode(topTags, forKey: .topTags)
        }
        
        // MARK: - Private
    }
    
    struct SimilarRow: Encodable {
        // MARK: - Property
        let id, axis, title: String
        let summary: String?
        let section: String?
        let tags: [String]?
        let path: String?
        var body: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct LinkedRow: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, axis, title, summary, weight, path
            case rankWeight = "rank_weight"
        }
        
        // MARK: - Property
        let id, axis, title: String
        let summary: String?
        let weight: Double
        let path: String?
        let rankWeight: Double?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct EntityHit: Encodable {
        enum CodingKeys: String, CodingKey {
            case entity, axis, title, summary
            case noteId = "note_id"
            case lastSeenAt = "last_seen_at"
            case hitCount = "hit_count"
        }
        
        // MARK: - Property
        let entity, noteId: String
        let axis: String?
        let hitCount: Int
        let summary: String?
        let lastSeenAt: Int?
        let title: String?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct Output: Encodable {
        enum CodingKeys: String, CodingKey {
            case keywords, axes, similar, linked, cooccur, vocab, degraded
            case vectorLinked = "vector_linked"
            case topTags = "top_tags"
            case entityHints = "entity_hints"
            case entityHits = "entity_hits"
        }
        
        // MARK: - Property
        let keywords: [String]
        let similar: [SimilarRow]
        let linked: [LinkedRow]
        let vectorLinked: [VectorLinkedRow]
        let topTags: [TagCount]
        let entityHits: [EntityHit]
        let degraded: [String]?
        let axes: [AxisRow]?
        let cooccur: [CooccurRow]?
        let vocab: [String]?
        let entityHints: [String]?
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "related",
        abstract: "Snapshot from free-form text — keywords, axes, similar, links, entity hits, archive cues.",
        discussion: """
            Primary entry point for capture and retrieval agents. Reads JSON
            from --json or stdin.

            INPUT
                text                  free-form input (preferred)
                user_input            concatenated when `text` is empty
                agent_output          concatenated when `text` is empty
                kind                  optional link-kind hint
                include_bodies        bool; inline note body for each similar
                include_candidates    bool; include local merge candidates
                candidates_limit      int

            EXAMPLES
                echo '{"text":"slack auth issue"}' \\
                    | llmemory query related --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Input JSON. Reads stdin if omitted.")
    var input: String?
    
    @Flag(name: .long, help: "Raise the data level: adds tags/path/last_seen, the axes/cooccur/vocab/entity_hints sections, and lifts row caps — same fields in plain and --json.")
    var verbose: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let payload = try readJSON(input) ?? [:]
        var text = payload["text"] as? String ?? ""
        
        if text.isEmpty {
            let parts = [payload["user_input"] as? String, payload["agent_output"] as? String]
                .compactMap { part in part }
                .filter { part in !part.isEmpty }
            text = parts.joined(separator: "\n")
        }
        
        let kind = payload["kind"] as? String
        let includeBodies = (payload["include_bodies"] as? Bool) ?? false
        let result = try await brain.query.related(
            text: text,
            kind: kind,
            cliSessionId: global.sessionId,
            includeBodies: includeBodies
        )
        let snapshot = result.snapshot
        let full = verbose
        let topTags = full ? snapshot.topTags[...] : snapshot.topTags.prefix(10)
        let entityHits = full ? snapshot.entityHits[...] : snapshot.entityHits.prefix(10)
        let output = Output(
            keywords: snapshot.keywords,
            similar: snapshot.similar.map { note in
                SimilarRow(
                    id: note.id,
                    axis: note.axis,
                    title: note.title,
                    summary: note.summary,
                    section: note.section,
                    tags: full ? note.tags : nil,
                    path: full ? note.path : nil,
                    body: result.bodies[note.id]
                )
            },
            linked: snapshot.linked.map { note in
                LinkedRow(
                    id: note.id,
                    axis: note.axis,
                    title: note.title,
                    summary: note.summary,
                    weight: note.weight,
                    path: full ? note.path : nil,
                    rankWeight: full ? note.rankWeight : nil
                )
            },
            vectorLinked: snapshot.vectorLinked.map { note in
                VectorLinkedRow(
                    id: note.id,
                    axis: note.axis,
                    title: note.title,
                    summary: note.summary,
                    cosine: note.score,
                    path: full ? note.path : nil
                )
            },
            topTags: topTags.map { tag in TagCount(tag: tag.0, count: tag.1) },
            entityHits: entityHits.map { hit in
                EntityHit(
                    entity: hit.entity,
                    noteId: hit.noteId,
                    axis: hit.axis,
                    hitCount: hit.hitCount,
                    summary: hit.summary,
                    lastSeenAt: full ? hit.lastSeenAt : nil,
                    title: full ? hit.title : nil
                )
            },
            degraded: snapshot.degraded.isEmpty ? nil : snapshot.degraded,
            axes: full
                ? snapshot.axes.map { axis in
                    AxisRow(
                        axis: axis.axis,
                        count: axis.count,
                        description: axis.description,
                        topTags: axis.topTags
                    )
                }
                : nil,
            cooccur: full
                ? snapshot.cooccur.map { pair in
                    CooccurRow(a: pair.0, b: pair.1, count: pair.2)
                }
                : nil,
            vocab: full ? snapshot.vocab : nil,
            entityHints: full ? snapshot.entityHints : nil
        )
        
        render(output, json: format.json) { output in
            var blocks: [PlainBlock] = []
            
            if let degraded = output.degraded, !degraded.isEmpty {
                blocks.append(.section("DEGRADED — 보강 실패 (빈 것 아님)"))
                
                for reason in degraded { blocks.append(.text("  " + reason)) }
            }
            
            if !output.keywords.isEmpty {
                blocks.append(.section("keywords"))
                blocks.append(.text("  " + output.keywords.joined(separator: ", ")))
            }
            
            if !output.topTags.isEmpty {
                blocks.append(.section("top tags"))
                blocks.append(
                    .table(
                        output.topTags.map { tag in [tag.tag, String(tag.count)] },
                        headers: ["tag", "count"]
                    )
                )
            }
            
            if let axes = output.axes, !axes.isEmpty {
                blocks.append(.section("axes (\(axes.count))"))
                blocks.append(
                    .table(
                        axes.map { axis in
                            [
                                axis.axis,
                                String(axis.count),
                                axis.topTags.joined(separator: ","),
                                axis.description ?? ""
                            ]
                        },
                        headers: ["axis", "count", "top_tags", "description"]
                    )
                )
            }
            
            if !output.similar.isEmpty {
                blocks.append(.section("similar (\(output.similar.count))"))
                blocks.append(
                    full
                        ? .table(
                            output.similar.map { row in
                                [
                                    row.axis,
                                    row.id,
                                    row.title,
                                    (row.tags ?? []).joined(separator: ","),
                                    row.section ?? "",
                                    row.path ?? "",
                                    row.summary ?? ""
                                ]
                            },
                            headers: [
                                "axis", "id", "title", "tags", "section", "path", "summary"
                            ]
                        )
                        : .table(
                            output.similar.map { row in
                                [
                                    row.axis,
                                    row.id,
                                    row.title,
                                    row.section ?? "",
                                    row.summary ?? ""
                                ]
                            },
                            headers: ["axis", "id", "title", "section", "summary"]
                        )
                )
                
                for row in output.similar where row.body != nil {
                    blocks.append(.section("body: \(row.id)"))
                    blocks.append(.text(row.body ?? ""))
                }
            }
            
            if !output.linked.isEmpty {
                blocks.append(.section("linked (\(output.linked.count))"))
                blocks.append(
                    full
                        ? .table(
                            output.linked.map { row in
                                [
                                    row.axis,
                                    row.id,
                                    String(format: "%.2f", row.weight),
                                    row.rankWeight.map { weight in
                                        String(format: "%.2f", weight)
                                    } ?? "",
                                    row.title,
                                    row.path ?? "",
                                    row.summary ?? ""
                                ]
                            },
                            headers: [
                                "axis", "id", "weight", "rank_w", "title", "path", "summary"
                            ]
                        )
                        : .table(
                            output.linked.map { row in
                                [
                                    row.axis,
                                    row.id,
                                    String(format: "%.2f", row.weight),
                                    row.title,
                                    row.summary ?? ""
                                ]
                            },
                            headers: ["axis", "id", "weight", "title", "summary"]
                        )
                )
            }
            
            if !output.vectorLinked.isEmpty {
                blocks.append(.section("vector linked (\(output.vectorLinked.count))"))
                blocks.append(
                    full
                        ? .table(
                            output.vectorLinked.map { row in
                                [
                                    row.axis,
                                    row.id,
                                    String(format: "%.2f", row.cosine),
                                    row.title,
                                    row.path ?? "",
                                    row.summary ?? ""
                                ]
                            },
                            headers: ["axis", "id", "cosine", "title", "path", "summary"]
                        )
                        : .table(
                            output.vectorLinked.map { row in
                                [
                                    row.axis,
                                    row.id,
                                    String(format: "%.2f", row.cosine),
                                    row.title,
                                    row.summary ?? ""
                                ]
                            },
                            headers: ["axis", "id", "cosine", "title", "summary"]
                        )
                )
            }
            
            if !output.entityHits.isEmpty {
                blocks.append(.section("entity hits (\(output.entityHits.count))"))
                blocks.append(
                    full
                        ? .table(
                            output.entityHits.map { hit in
                                [
                                    hit.entity,
                                    hit.axis ?? "-",
                                    hit.noteId,
                                    String(hit.hitCount),
                                    hit.lastSeenAt.map(dayString) ?? "-",
                                    hit.summary ?? ""
                                ]
                            },
                            headers: [
                                "entity", "axis", "note_id", "hits", "last_seen", "summary"
                            ]
                        )
                        : .table(
                            output.entityHits.map { hit in
                                [
                                    hit.entity,
                                    hit.axis ?? "-",
                                    hit.noteId,
                                    String(hit.hitCount),
                                    hit.summary ?? ""
                                ]
                            },
                            headers: ["entity", "axis", "note_id", "hits", "summary"]
                        )
                )
            }
            
            if let hints = output.entityHints, !hints.isEmpty {
                blocks.append(.section("entity hints"))
                blocks.append(.text("  " + hints.joined(separator: ", ")))
            }
            
            if let cooccur = output.cooccur, !cooccur.isEmpty {
                blocks.append(.section("cooccur (\(cooccur.count))"))
                blocks.append(
                    .table(
                        cooccur.map { pair in [pair.a, pair.b, String(pair.count)] },
                        headers: ["a", "b", "count"]
                    )
                )
            }
            
            if let vocab = output.vocab, !vocab.isEmpty {
                blocks.append(.section("vocab (\(vocab.count))"))
                blocks.append(.text("  " + vocab.joined(separator: ", ")))
            }
            
            return blocks
        }
    }
    
    // MARK: - Private
}

struct QuerySearch: AsyncParsableCommand {
    struct Row: Encodable {
        // MARK: - Property
        let axis, id, title: String
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
        let id, axis, title: String
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
                llmemory query search "transfer" --axis tech --limit 10 --home brain
                llmemory query search "transfer NOT giro" --raw --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Argument(help: "FTS5 query string.")
    var query: String
    
    @Option(name: .long, help: "Restrict to a single axis.")
    var axis: String?
    
    @Option(name: .long, help: "Max rows returned (default 5).")
    var limit: Int = 5
    
    @Option(name: .long, help: "Pull N additional 2-hop linked notes (default 0).")
    var expand: Int = 0
    
    @Flag(name: .long, help: "Include notes marked stale.")
    var includeStale: Bool = false
    
    @Option(name: .long, parsing: .upToNextOption, help: "Axes to exclude from search.")
    var excludeAxes: [String] = []
    
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
            axis: axis,
            limit: limit,
            expand: expand,
            cliSessionId: global.sessionId,
            includeStale: includeStale,
            excludeAxes: excludeAxes,
            raw: raw
        )
        let output = Output(
            rows: rows.map { row in
                Row(
                    axis: row.axis,
                    id: row.id,
                    title: row.title,
                    summary: row.summary,
                    section: row.section,
                    path: verbose ? row.path : nil,
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
                    axis: note.axis,
                    title: note.title,
                    summary: note.summary,
                    weight: note.weight,
                    path: verbose ? note.path : nil
                )
            }
        )
        
        render(output, json: format.json) { output -> [PlainBlock] in
            var blocks: [PlainBlock] = [
                verbose
                    ? .table(
                        output.rows.map { row in
                            [
                                row.axis,
                                row.id,
                                row.title + (row.stale == true ? "  [stale]" : ""),
                                (row.tags ?? []).joined(separator: ","),
                                row.section ?? "",
                                row.path ?? "",
                                row.summary ?? ""
                            ]
                        },
                        headers: ["axis", "id", "title", "tags", "section", "path", "summary"]
                    )
                    : .table(
                        output.rows.map { row in
                            [row.axis, row.id, row.title, row.section ?? "", row.summary ?? ""]
                        },
                        headers: ["axis", "id", "title", "section", "summary"]
                    )
            ]
            
            if !output.expanded.isEmpty {
                blocks.append(.section("expanded (\(output.expanded.count))"))
                blocks.append(
                    verbose
                        ? .table(
                            output.expanded.map { note in
                                [
                                    note.axis,
                                    note.id,
                                    String(format: "%.2f", note.weight),
                                    note.title,
                                    note.path ?? "",
                                    note.summary ?? ""
                                ]
                            },
                            headers: ["axis", "id", "weight", "title", "path", "summary"]
                        )
                        : .table(
                            output.expanded.map { note in
                                [
                                    note.axis,
                                    note.id,
                                    String(format: "%.2f", note.weight),
                                    note.title,
                                    note.summary ?? ""
                                ]
                            },
                            headers: ["axis", "id", "weight", "title", "summary"]
                        )
                )
            }
            
            return blocks
        }
    }
    
    // MARK: - Private
}

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
        let axis: String
        let path: String
        let frontmatter: QueryFeature.NoteFrontmatter
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
        let axis: String
        let path: String
        let toc: [TocRow]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct BudgetOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, axis, path, frontmatter, body, truncated, stats
            case shownWords = "shown_words"
            case totalWords = "total_words"
            case shownSections = "shown_sections"
            case omittedSections = "omitted_sections"
            case truncatedWithin = "truncated_within"
        }
        
        // MARK: - Property
        let id: String
        let axis: String
        let path: String
        let frontmatter: QueryFeature.NoteFrontmatter
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
    
    @Argument(help: "Note ids (kebab-case, match filenames).")
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
                axis: note.axis,
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
        
        render(outputs, json: format.json) { outputs in
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
            sections: section
        )
        let output = Output(
            id: note.id,
            axis: note.axis,
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
        
        render([output], json: format.json) { outputs in
            outputs.flatMap { output in
                [.keyValue(headerPairs(output)), .blank, .text(output.body)]
            }
        }
    }
    
    private func runBudget(_ budget: Int) async throws {
        let brain = Brain(home: global.home)
        
        let (note, cut) = try await brain.query.getBudget(
            id: ids[0],
            budget: budget
        )
        let output = BudgetOutput(
            id: note.id,
            axis: note.axis,
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
        
        render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .keyValue(
                    headerPairs(
                        Output(
                            id: output.id,
                            axis: output.axis,
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
        
        let (note, entries) = try await brain.query.toc(id: ids[0])
        let output = TocOutput(
            id: note.id,
            axis: note.axis,
            path: note.path,
            toc: entries.map { entry in TocRow(section: entry.path, words: entry.words) }
        )
        
        render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .keyValue([("id", output.id), ("axis", output.axis), ("path", output.path)]),
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
            ("axis", output.axis),
            ("path", output.path),
            ("priority", output.stats.priority),
            ("hits", String(output.stats.hitCount))
        ]
        
        if let createdAt = output.stats.createdAt {
            pairs.append(("created", dayString(createdAt)))
        }
        
        if let editedAt = output.stats.editedAt {
            pairs.append(("edited", dayString(editedAt)))
        }
        
        if let sections = output.sections {
            pairs.append(("sections", sections.joined(separator: " | ")))
        }
        
        return pairs
    }
}

struct QueryMeta: AsyncParsableCommand {
    struct ByIdOutput: Encodable {
        // MARK: - Property
        let id: String
        let meta: [String: [String: String]]
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct ByKVRow: Encodable {
        enum CodingKeys: String, CodingKey {
            case noteId = "note_id"
            case value
        }
        
        // MARK: - Property
        let noteId: String
        let value: String
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "meta",
        abstract: "Read namespaced plugin metadata (note_meta).",
        discussion: """
            Two modes.

            MODES
                --id <note>                              All kv for one note.
                --namespace <ns> --key <k> [--value v]   Find notes by kv match.

            EXAMPLES
                llmemory query meta --id journal-260508 --home brain
                llmemory query meta --namespace journal --key affect --value high --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Note id (mode 1).")
    var id: String?
    
    @Option(name: .long, help: "Plugin namespace (mode 2).")
    var namespace: String?
    
    @Option(name: .long, help: "Meta key (mode 2).")
    var key: String?
    
    @Option(name: .long, help: "Filter by value (mode 2, optional).")
    var value: String?
    
    @Option(name: .long, help: "Max rows in mode 2 (default 100).")
    var limit: Int = 100
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        if let id {
            let data = try await brain.query.metaById(
                noteId: id,
                namespace: namespace
            )
            
            render(ByIdOutput(id: id, meta: data), json: format.json) { output in
                var pairs: [(String, String)] = [("note_id", output.id)]
                
                for (namespace, values) in output.meta.sorted(by: { lhs, rhs in
                    lhs.key < rhs.key
                }) {
                    for (key, value) in values.sorted(by: { lhs, rhs in lhs.key < rhs.key }) {
                        pairs.append(("\(namespace).\(key)", value))
                    }
                }
                
                return [.keyValue(pairs)]
            }
            
            return
        }
        
        guard let namespace, let key else {
            FileHandle.standardError.write(
                "either --id or (--namespace + --key) is required\n".data(using: .utf8)!
            )
            
            throw ExitCode(2)
        }
        
        let rows = try await brain.query.metaByKV(
            namespace: namespace,
            key: key,
            value: value,
            limit: limit
        )
        
        render(
            rows.map { row in ByKVRow(noteId: row.noteId, value: row.value) },
            json: format.json
        ) { rows in
            [.table(rows.map { row in [row.noteId, row.value] }, headers: ["note_id", "value"])]
        }
    }
    
    // MARK: - Private
}

struct QueryEntity: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "entity",
        abstract: "Reverse lookup: entity → notes.",
        discussion: """
            Notes mentioning an entity in body, ordered by last_seen_at. Used
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
        
        let rows = try await brain.query.entity(name: name, limit: limit)
        
        render(rows, json: format.json) { rows in
            [
                .table(
                    rows.map { row in
                        [
                            row.entity,
                            row.axis ?? "-",
                            row.noteId,
                            String(row.hitCount),
                            row.summary ?? ""
                        ]
                    },
                    headers: ["entity", "axis", "note_id", "hits", "summary"]
                )
            ]
        }
    }
    
    // MARK: - Private
}

struct QueryStructure: AsyncParsableCommand {
    struct AxisRow: Encodable {
        enum CodingKeys: String, CodingKey {
            case axis, description, count
        }
        
        // MARK: - Property
        let axis: String
        let description: String?
        let count: Int
        
        // MARK: - Initializer
        // MARK: - Public
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(axis, forKey: .axis)
            try container.encode(description, forKey: .description)
            try container.encode(count, forKey: .count)
        }
        
        // MARK: - Private
    }
    
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
        let id, axis, title: String
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
            case axes, links
            case axisStats = "axis_stats"
        }
        
        // MARK: - Property
        let axes: [AxisRow]
        let links: LinksReport
        let axisStats: QueryStats.AxisOutput?
        
        // MARK: - Initializer
        // MARK: - Public
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(axes, forKey: .axes)
            try container.encode(links, forKey: .links)
            
            if let axisStats { try container.encode(axisStats, forKey: .axisStats) }
        }
        
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "structure",
        abstract: "Memory topology — axes, link distribution, top-degree notes.",
        discussion: """
            Useful before running consolidation. Pass --axis for per-axis stats.

            EXAMPLES
                llmemory query structure --home brain
                llmemory query structure --axis flow --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Add stats for a specific axis.")
    var axis: String?
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let structure = try await brain.query.structure(axis: axis)
        let distribution = structure.distribution
        let stats: QueryStats.AxisOutput? = structure.axisStats.map { stats in
            QueryStats.AxisOutput(
                axis: stats.axis,
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
            axes: structure.axes.map { entry in
                AxisRow(axis: entry.axis, description: entry.description, count: entry.count)
            },
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
                        axis: entry.axis,
                        title: entry.title,
                        degree: entry.degree
                    )
                }
            ),
            axisStats: stats
        )
        
        render(output, json: format.json) { output in
            var blocks: [PlainBlock] = [
                .section("axes (\(output.axes.count))"),
                .table(
                    output.axes.map { row in
                        [row.axis, String(row.count), row.description ?? ""]
                    },
                    headers: ["axis", "count", "description"]
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
                            [row.axis, row.id, String(row.degree), row.title]
                        },
                        headers: ["axis", "id", "degree", "title"]
                    )
                )
            }
            
            if let stats = output.axisStats {
                blocks.append(.section("axis '\(stats.axis)' stats"))
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

struct QueryNeighbors: AsyncParsableCommand {
    struct Item: Encodable {
        // MARK: - Property
        let id: String
        let axis: String
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
                axis: score.axis,
                title: score.title,
                summary: score.summary,
                score: score.score,
                fts: verbose ? score.fts : nil,
                entity: verbose ? score.entity : nil,
                link: verbose ? score.link : nil
            )
        }
        
        render(items, json: format.json) { items -> [PlainBlock] in
            guard verbose else {
                return [
                    .table(
                        items.map { item in
                            [
                                item.axis,
                                item.id,
                                String(format: "%.2f", item.score),
                                item.title,
                                item.summary ?? ""
                            ]
                        },
                        headers: ["axis", "id", "score", "title", "summary"]
                    )
                ]
            }
            
            return [
                .table(
                    items.map { item in
                        [
                            item.axis,
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
                        "axis", "id", "score", "fts", "entity", "link", "title", "summary"
                    ]
                )
            ]
        }
    }
    
    // MARK: - Private
}

struct QueryStats: AsyncParsableCommand {
    struct NoteOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case id, axis, title, summary, priority, stale
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
        let id, axis, title: String
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
    
    struct AxisOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case axis, total, stale, eager
            case avgWords = "avg_words"
            case maxWords = "max_words"
            case avgSections = "avg_sections"
            case totalHits = "total_hits"
        }
        
        // MARK: - Property
        let axis: String
        let total, stale, eager: Int
        let avgWords: Double
        let maxWords: Int
        let avgSections: Double
        let totalHits: Int
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    struct AxisCount: Encodable {
        // MARK: - Property
        let axis: String
        let count: Int
        
        // MARK: - Initializer
        // MARK: - Public
        func encode(to encoder: Encoder) throws {
            var container = encoder.unkeyedContainer()
            
            try container.encode(axis)
            try container.encode(count)
        }
        
        // MARK: - Private
    }
    
    struct OverallOutput: Encodable {
        enum CodingKeys: String, CodingKey {
            case total, stale, axes
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
        let axes: [AxisCount]
        let hitNonZero, hitZero: Int
        let hitAvg: Double
        let hitMax: Int
        let avgWords: Double
        let maxWords: Int
        let avgSections: Double
        let activation: Activation.Stats
        
        // MARK: - Initializer
        // MARK: - Public
        // MARK: - Private
    }
    
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Note / axis / overall counters and rates.",
        discussion: """
            Three modes determined by which option is set.

            MODES
                --id <note>   Per-note stats (age, hits, sections, tags, links).
                --axis <a>    Per-axis aggregates.
                (neither)     Overall stats.

            EXAMPLES
                llmemory query stats --home brain
                llmemory query stats --id principles --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Per-note stats.")
    var id: String?
    
    @Option(name: .long, help: "Per-axis stats.")
    var axis: String?
    
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
                axis: stats.axis,
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
            
            render(output, json: format.json) { output -> [PlainBlock] in
                let pairs: [(String, String)] = [
                    ("id", output.id),
                    ("axis", output.axis),
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
        } else if let axis {
            let stats = try await brain.query.axisStats(axis: axis)
            let output = AxisOutput(
                axis: stats.axis,
                total: stats.total,
                stale: stats.stale,
                eager: stats.eager,
                avgWords: stats.avgWords,
                maxWords: stats.maxWords,
                avgSections: stats.avgSections,
                totalHits: stats.totalHits
            )
            
            render(output, json: format.json) { output -> [PlainBlock] in
                let pairs: [(String, String)] = [
                    ("axis", output.axis),
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
                axes: stats.axes.map { entry in
                    AxisCount(axis: entry.axis, count: entry.count)
                },
                hitNonZero: stats.hitNonZero,
                hitZero: stats.hitZero,
                hitAvg: stats.hitAvg,
                hitMax: stats.hitMax,
                avgWords: stats.avgWords,
                maxWords: stats.maxWords,
                avgSections: stats.avgSections,
                activation: stats.activation
            )
            
            render(output, json: format.json) { output -> [PlainBlock] in
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
                    .section("by axis"),
                    .table(
                        output.axes.map { entry in [entry.axis, String(entry.count)] },
                        headers: ["axis", "count"]
                    ),
                    .section("activation"),
                    .keyValue(activationPairs),
                    .table(
                        activation.byAxis.map { entry in
                            [entry.axis, String(entry.surfaced), String(entry.used)]
                        },
                        headers: ["axis", "surfaced", "used"]
                    )
                ]
            }
        }
    }
    
    // MARK: - Private
}

struct QueryList: AsyncParsableCommand {
    struct Row: Encodable {
        enum CodingKeys: String, CodingKey {
            case axis, id, title, summary, priority, stale
            case sourceStale = "source_stale"
            case createdAt = "created_at"
            case editedAt = "edited_at"
        }
        
        // MARK: - Property
        let axis, id, title: String
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

            Plain output is a table (axis, id, title, summary). For scripted
            id extraction use --json (adds lifecycle fields) and parse.


            EXAMPLES
                llmemory query list --priority eager --home brain
                llmemory query list --stale --axis persona --home brain
                llmemory query list --axis skill --json --home brain
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Match a priority (e.g. eager).")
    var priority: String?
    
    @Option(name: .long, help: "Match a single axis.")
    var axis: String?
    
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
        let brain = Brain(home: global.home)
        
        let rows = try await brain.query.list(
            priority: priority,
            axis: axis,
            stale: stale,
            sourceStale: sourceStale,
            limit: limit
        )
        let output = rows.map { row in
            Row(
                axis: row.axis,
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
        
        render(output, json: format.json) { rows -> [PlainBlock] in
            guard verbose else {
                return [
                    .table(
                        rows.map { row in [row.axis, row.id, row.title, row.summary ?? ""] },
                        headers: ["axis", "id", "title", "summary"]
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
                            row.axis,
                            row.id,
                            row.priority ?? "",
                            flags.joined(separator: ","),
                            dayString(row.createdAt ?? 0),
                            dayString(row.editedAt ?? 0),
                            row.title,
                            row.summary ?? ""
                        ]
                    },
                    headers: [
                        "axis", "id", "priority", "flags", "created", "edited", "title", "summary"
                    ]
                )
            ]
        }
    }
    
    // MARK: - Private
}

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
        
        render(rows, json: format.json) { rows in
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

struct QueryLint: AsyncParsableCommand {
    // MARK: - Property
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Rule-based consistency check (frontmatter, axis/tag policy, links).",
        discussion: """
            Deterministic checks only — reports facts, never decides. Two severities:
            `error` = invariant violations (integrity gate), `warn` = quality facts
            (improvement queue). Slice by --severity / --code / --limit so each consumer
            pulls only its rows.

            A warn is a judgment request. Once reviewed and kept, close it with
            `dismiss_candidate kind="lint:<code>"` and it stops re-surfacing until the note's
            shape diverges or a corpus reorg reopens it — otherwise the same finding is
            re-litigated every cycle. `--include-dismissed` shows the suppressed ones.
            Errors are never dismissible or suppressed.

            `subject` is what the finding is about, and `target_scope` (json) says which kind:
            `note` = a note id (dismiss with `id`), `corpus` = a fact no note owns, such as
            a tag pair (dismiss with `target`, and only a corpus reorg reopens it).

            EXIT STATUS
                0   no errors in the returned set
                1   one or more errors in the returned set

            EXAMPLES
                llmemory query lint --home brain
                llmemory query lint --severity error --home brain        # integrity gate
                llmemory query lint --code enrich-thin --limit 10 --home brain
                llmemory query lint --id principles --home brain
                llmemory query lint --rules --home brain                 # rule catalog
                llmemory query lint --include-dismissed --home brain     # incl. kept warns
            """
    )
    
    @OptionGroup var global: GlobalHomeOptions
    @OptionGroup var format: OutputFormat
    
    @Option(name: .long, help: "Lint only this note (default: all).")
    var id: String?
    
    @Option(name: .long, help: "Only this issue code (e.g. enrich-thin).")
    var code: String?
    
    @Option(name: .long, help: "Only this severity (error|warn).")
    var severity: String?
    
    @Option(name: .long, help: "Cap rows returned (default: no cap).")
    var limit: Int?
    
    @Flag(name: .long, help: "List registered rules (code, severity, scope) instead of linting.")
    var rules: Bool = false
    
    @Flag(name: .long, help: "Include warns closed by dismiss_candidate.")
    var includeDismissed: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        if rules {
            let catalog = Lint.ruleCatalog()
            
            render(catalog, json: format.json) { rules in
                [
                    .table(
                        rules.map { rule in [rule.severity, rule.code, rule.scope] },
                        headers: ["sev", "code", "scope"]
                    )
                ]
            }
            
            return
        }
        
        let issues = try await brain.query.lint(
            id: id,
            code: code,
            severity: severity,
            limit: limit,
            includeDismissed: includeDismissed
        )
        
        render(issues, json: format.json) { issues in
            [
                .table(
                    issues.map { issue in
                        [issue.severity, issue.target.subject, issue.code, issue.message]
                    },
                    headers: ["sev", "subject", "code", "message"]
                )
            ]
        }
        
        if issues.contains(where: { issue in issue.severity == "error" }) {
            throw ExitCode(1)
        }
    }
    
    // MARK: - Private
}
