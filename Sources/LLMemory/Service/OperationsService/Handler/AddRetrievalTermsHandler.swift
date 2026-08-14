//
//  AddRetrievalTermsHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct AddRetrievalTermsHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "attach LLM-emitted retrieval terms (alias/cue) to a note — inserted as status=pending, then promoted to active/rejected by llmemory's own round-trip + IDF validation pass (LLM never decides). 'alias' = synonym/abbrev/한↔영 짝/조사 뗀 어근 covering BM25 synonymy blind spots; 'cue' = a question this note would answer (write-time HyDE). Active terms are indexed into notes_fts.enrich and become searchable with no read-time cost.",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("kind", "'alias' | 'cue'"),
            .required("terms", "non-empty string list of alias phrases or cue questions (capped by config enrich.max_terms_per_op, default 12)"),
            .optional("provenance", "producer id, e.g. 'forge:capture:claude-sonnet-4-6'; used for batch audit + purge_enrichment recall")
        ],
        example: ##"{"op":"add_retrieval_terms","id":"my-note","kind":"alias","terms":["검색 동의어","retrieval synonym"],"provenance":"forge:capture:claude-sonnet-4-6"}"##
    )

    private let payload = OpPayloadCheck()

    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let noteId = op["id"] as? String ?? ""

        if let rejection = try payload.checkIDKnown(noteId, context: context, scope: scope) {
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
    }

    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let now = context.now
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
            inserted += try scope.run(UpsertPendingTermTransaction(
                noteId: noteId,
                kind: kind,
                term: term,
                provenance: provenance,
                now: now
            ))
        }

        return [
            "status": "ok",
            "ids": [noteId],
            "note": "added \(inserted) \(kind) term(s) (pending validation)"
        ]
    }

    // MARK: - Private
}
