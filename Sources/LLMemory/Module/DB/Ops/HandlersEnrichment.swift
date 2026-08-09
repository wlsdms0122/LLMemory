//
//  HandlersEnrichment.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum HandlersEnrichment {
    // MARK: - Property
    public static let addRetrievalTerms = OpHandler(
        schema: OpSchema(
            summary: "attach LLM-emitted retrieval terms (alias/cue) to a note — inserted as status=pending, then promoted to active/rejected by llmemory's own round-trip + IDF validation pass (LLM never decides). 'alias' = synonym/abbrev/한↔영 짝/조사 뗀 어근 covering BM25 synonymy blind spots; 'cue' = a question this note would answer (write-time HyDE). Active terms are indexed into notes_fts.enrich and become searchable with no read-time cost.",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("kind", "'alias' | 'cue'"),
                .required("terms", "non-empty string list of alias phrases or cue questions (capped by config enrich.max_terms_per_op, default 12)"),
                .optional("provenance", "producer id, e.g. 'forge:capture:claude-sonnet-4-6'; used for batch audit + purge_enrichment recall")
            ],
            example: ##"{"op":"add_retrieval_terms","id":"my-note","kind":"alias","terms":["검색 동의어","retrieval synonym"],"provenance":"forge:capture:claude-sonnet-4-6"}"##
        ),
        validate: { op, context, db in
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, db: db) {
                return rejection
            }
            
            let kind = op["kind"] as? String ?? ""
            
            if kind != "alias" && kind != "cue" {
                return "invalid kind: \(kind) (expected 'alias' or 'cue')"
            }
            
            guard let terms = op["terms"] as? [Any], !terms.isEmpty else {
                return "terms must be non-empty list"
            }
            
            let phrases = terms
                .compactMap { term in term as? String }
                .filter { term in !term.trimmingCharacters(in: .whitespaces).isEmpty }
            
            if phrases.isEmpty { return "terms must contain at least one non-empty string" }
            
            let capacity = Config.getInt("enrich.max_terms_per_op", default: 12)
            
            if phrases.count > capacity {
                return "too many terms: \(phrases.count) (cap \(capacity) — see config enrich.max_terms_per_op)"
            }
            
            return nil
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let noteId = op["id"] as! String
            let kind = op["kind"] as! String
            let provenance = (op["provenance"] as? String)
                .flatMap { value in value.isEmpty ? nil : value }
            let terms = (op["terms"] as? [Any])?
                .compactMap { term in term as? String }
                .map { term in term.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { term in !term.isEmpty } ?? []
            var inserted = 0
            
            for term in terms {
                inserted += try UpsertPendingTermTransaction(
                    noteId: noteId,
                    kind: kind,
                    term: term,
                    provenance: provenance,
                    now: now
                )
                    .perform(db)
            }
            
            return [
                "status": "ok",
                "ids": [noteId],
                "note": "added \(inserted) \(kind) term(s) (pending validation)"
            ]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let proposeLink = OpHandler(
        schema: OpSchema(
            summary: "propose an LLM semantic-association edge (kind=assoc) between two notes at a low dormant weight. No separate validation: the edge starts BELOW the traversal floor (links.neighbor_floor 0.5) so retrieval ignores it until co-retrieval strengthens it past 0.5; if never used, decay prunes it. The existing Hebbian decay/strengthen loop IS the validator (synaptic pruning).",
            fields: [
                .required("src", role: .noteId, "source note id"),
                .required("dst", role: .noteId, "destination note id (must differ from src)"),
                .optional("kind", "link kind — only 'assoc' is accepted; default 'assoc'"),
                .optional("provenance", "producer id; used for batch audit + purge_enrichment recall"),
                .optional("confidence", "(0,1] LLM self-reported confidence; uncalibrated, so it only positions the initial weight within the dormant band [links.proposed_initial_weight, links.neighbor_floor) — higher = closer to the traversal floor, never at or above it. Default 1.0.")
            ],
            example: ##"{"op":"propose_link","src":"note-a","dst":"note-b","kind":"assoc","confidence":0.8,"provenance":"forge:capture:claude-sonnet-4-6"}"##
        ),
        validate: { op, context, db in
            let src = op["src"] as? String ?? ""
            let dst = op["dst"] as? String ?? ""
            
            if src == dst { return "src and dst must differ" }
            
            if let rawKind = op["kind"] {
                let kind = rawKind as? String ?? ""
                
                if kind != Links.kindAssoc {
                    return "invalid kind: \(kind) (propose_link only supports 'assoc')"
                }
            }
            
            if let rejection = try Handlers.checkIDKnown(src, context: context, db: db) {
                return "src: \(rejection)"
            }
            
            if let rejection = try Handlers.checkIDKnown(dst, context: context, db: db) {
                return "dst: \(rejection)"
            }
            
            if let rawConfidence = op["confidence"] {
                guard let confidence = (rawConfidence as? Double)
                    ?? (rawConfidence as? Int).map(Double.init),
                    confidence > 0, confidence <= 1
                else {
                    return "confidence must be a number in (0, 1]"
                }
            }
            
            return nil
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let src = op["src"] as! String
            let dst = op["dst"] as! String
            let kind = (op["kind"] as? String)
                .flatMap { value in value.isEmpty ? nil : value } ?? Links.kindAssoc
            let provenance = (op["provenance"] as? String)
                .flatMap { value in value.isEmpty ? nil : value }
            let confidence: Double = {
                if let double = op["confidence"] as? Double { return double }
                if let int = op["confidence"] as? Int { return Double(int) }
                
                return 1.0
            }()
            let base = Genome.double("links.proposed_initial_weight")
            let neighborFloor = Genome.double("links.neighbor_floor")
            let ceiling = neighborFloor - 0.02
            let weight = min(ceiling, base + max(0, ceiling - base) * confidence)
            
            guard let (source, destination) = Links.normalize(src: src, dst: dst, kind: kind) else {
                return ["status": "ok", "ids": [], "note": "skipped self-loop \(src)"]
            }
            
            try UpsertAssocLinkTransaction(
                src: source,
                dst: destination,
                kind: kind,
                weight: weight,
                now: now,
                provenance: provenance
            )
                .perform(db)
            
            return [
                "status": "ok",
                "ids": [source, destination],
                "note": "proposed \(kind) edge \(source)→\(destination) (weight \(String(format: "%.2f", weight)), dormant)"
            ]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let purgeEnrichment = OpHandler(
        schema: OpSchema(
            summary: "recall path for a noisy model/batch: reject every retrieval term and delete every assoc edge carrying the given provenance. Goes through the same transaction/ruleset gate as any op. Not a durable ban — a later re-proposal of a purged term re-opens it as pending (rows describe the latest proposal; validation re-judges it).",
            fields: [
                .required("provenance", "producer id to purge (matches note_retrieval_terms.provenance and note_links.provenance exactly)")
            ],
            example: ##"{"op":"purge_enrichment","provenance":"forge:capture:claude-sonnet-4-6"}"##
        ),
        validate: { _, _, _ in
            nil
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let provenance = op["provenance"] as! String
            let (termsPurged, edgesPurged, affected) = try PurgeEnrichmentProvenanceTransaction(
                provenance: provenance,
                now: now
            )
                .perform(db)
            
            return [
                "status": "ok",
                "ids": affected,
                "note": "purged \(termsPurged) term(s) + \(edgesPurged) edge(s) from provenance '\(provenance)'"
            ]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let linkLineage = OpHandler(
        schema: OpSchema(
            summary: "record a lineage fact between two notes (promoted_to / supersedes / merge_ancestor) "
            + "at full weight, decay-exempt. Use when a note was extracted from, replaces, or "
            + "descends from another — not for semantic association (that is propose_link).",
            fields: [
                .required("src", role: .noteId, "subject of the relation — read the edge as the sentence "
                    + "`src <kind> dst`, so which note goes here depends on the kind (see below)"),
                .required("dst", role: .noteId, "object of the relation"),
                .required("kind", "'promoted_to' (src=origin journal, dst=the note extracted from it) "
                    + "| 'supersedes' (src=the replacement, dst=what it replaces) "
                    + "| 'merge_ancestor' (src=surviving note, dst=the note merged away)"),
                .optional("reason", "why this lineage holds; recorded on src's lifecycle")
            ],
            example: ##"{"op":"link_lineage","src":"bk-5262-rc1-260524","dst":"deploy-approval-policy","kind":"promoted_to","reason":"회차 반복 패턴을 원리로 추출"}"##
        ),
        validate: { op, context, db in
            let kind = op["kind"] as? String ?? ""
            
            guard Links.lineageKinds.contains(kind) else {
                return "invalid lineage kind: \(kind) (expected \(Links.lineageKinds.sorted().joined(separator: " | ")))"
            }
            
            let src = op["src"] as? String ?? ""
            let dst = op["dst"] as? String ?? ""
            
            if src == dst { return "src and dst must differ: \(src)" }
            
            if let rejection = try Handlers.checkIDKnown(src, context: context, db: db) {
                return rejection
            }
            
            return try Handlers.checkIDKnown(dst, context: context, db: db)
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let src = op["src"] as! String
            let dst = op["dst"] as! String
            let kind = op["kind"] as! String
            
            try InsertLineageLinkTransaction(src: src, dst: dst, kind: kind, now: now).perform(db)
            
            let reason = op["reason"] as? String
            
            try RecordNoteLifecycleEventTransaction(nid: src, kind: kind, reason: reason, now: now).perform(db)
            
            return [
                "status": "ok",
                "ids": [src, dst],
                "note": "recorded \(kind): \(src) → \(dst)"
            ]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
