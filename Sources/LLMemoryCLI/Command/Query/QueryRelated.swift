//
//  QueryRelated.swift
//  LLMemoryCLI
//
//  Created by JSilver on 8/15/26.
//

import ArgumentParser
import Foundation
import LLMemory

struct QueryRelated: AsyncParsableCommand {
    struct VectorLinkedRow: Encodable {
        // MARK: - Property
        let id, title: String
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
    
    struct SimilarRow: Encodable {
        // MARK: - Property
        let id, title: String
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
            case id, title, summary, weight, path
            case rankWeight = "rank_weight"
        }
        
        // MARK: - Property
        let id, title: String
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
            case entity, title, summary
            case noteId = "note_id"
            case lastSeenAt = "last_seen_at"
            case hitCount = "hit_count"
        }
        
        // MARK: - Property
        let entity, noteId: String
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
            case keywords, similar, linked, cooccur, vocab, degraded
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
        abstract: "Snapshot from free-form text — keywords, similar, links, entity hits, archive cues.",
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
    
    @Flag(name: .long, help: "Raise the data level: adds tags/path/last_seen, the cooccur/vocab/entity_hints sections, and lifts row caps — same fields in plain and --json.")
    var verbose: Bool = false
    
    // MARK: - Initializer
    // MARK: - Public
    func run() async throws {
        let brain = Brain(home: global.home)
        
        let payload = try CommandInput().readJSON(input) ?? [:]
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
                    hitCount: hit.hitCount,
                    summary: hit.summary,
                    lastSeenAt: full ? hit.lastSeenAt : nil,
                    title: full ? hit.title : nil
                )
            },
            degraded: snapshot.degraded.isEmpty ? nil : snapshot.degraded,
            cooccur: full
                ? snapshot.cooccur.map { pair in
                    CooccurRow(a: pair.0, b: pair.1, count: pair.2)
                }
                : nil,
            vocab: full ? snapshot.vocab : nil,
            entityHints: full ? snapshot.entityHints : nil
        )
        
        CommandOutput().render(output, json: format.json) { output in
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
            
            if !output.similar.isEmpty {
                blocks.append(.section("similar (\(output.similar.count))"))
                blocks.append(
                    full
                        ? .table(
                            output.similar.map { row in
                                [
                                    row.id,
                                    row.title,
                                    (row.tags ?? []).joined(separator: ","),
                                    row.section ?? "",
                                    row.path ?? "",
                                    row.summary ?? ""
                                ]
                            },
                            headers: [
                                "id", "title", "tags", "section", "path", "summary"
                            ]
                        )
                        : .table(
                            output.similar.map { row in
                                [
                                    row.id,
                                    row.title,
                                    row.section ?? "",
                                    row.summary ?? ""
                                ]
                            },
                            headers: ["id", "title", "section", "summary"]
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
                                "id", "weight", "rank_w", "title", "path", "summary"
                            ]
                        )
                        : .table(
                            output.linked.map { row in
                                [
                                    row.id,
                                    String(format: "%.2f", row.weight),
                                    row.title,
                                    row.summary ?? ""
                                ]
                            },
                            headers: ["id", "weight", "title", "summary"]
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
                                    row.id,
                                    String(format: "%.2f", row.cosine),
                                    row.title,
                                    row.path ?? "",
                                    row.summary ?? ""
                                ]
                            },
                            headers: ["id", "cosine", "title", "path", "summary"]
                        )
                        : .table(
                            output.vectorLinked.map { row in
                                [
                                    row.id,
                                    String(format: "%.2f", row.cosine),
                                    row.title,
                                    row.summary ?? ""
                                ]
                            },
                            headers: ["id", "cosine", "title", "summary"]
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
                                    hit.noteId,
                                    String(hit.hitCount),
                                    hit.lastSeenAt.map { epoch in DayStamp().dayString(epoch) } ?? "-",
                                    hit.summary ?? ""
                                ]
                            },
                            headers: [
                                "entity", "note_id", "hits", "last_seen", "summary"
                            ]
                        )
                        : .table(
                            output.entityHits.map { hit in
                                [
                                    hit.entity,
                                    hit.noteId,
                                    String(hit.hitCount),
                                    hit.summary ?? ""
                                ]
                            },
                            headers: ["entity", "note_id", "hits", "summary"]
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
