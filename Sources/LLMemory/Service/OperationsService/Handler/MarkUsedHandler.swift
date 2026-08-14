//
//  MarkUsedHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct MarkUsedHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "mark recently surfaced notes as used in the caller's response — a *weak* usage "
        + "signal, never a proof of causal use. With `response` text each note must pass a "
        + "content-overlap heuristic and is recorded as `content_overlap`; without it the mark "
        + "is recorded as caller-`reported`. Notes not surfaced in a recent activity window are "
        + "rejected: usage of an unobserved note is not an observation.",
        fields: [
            .required("ids", role: .noteIdList, "note ids the response actually drew on (array)"),
            .optional("response", "the final response text — enables the content-overlap check; "
                + "omit to record a bare caller report")
        ],
        example: ##"{"op":"mark_used","ids":["transfer-flow","apigw-routing"],"response":"...최종 응답 본문..."}"##
    )
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        guard let raw = op["ids"] as? [Any], !raw.isEmpty else {
            return "ids must be a non-empty array of note ids"
        }
        
        let ids = raw.compactMap { value in value as? String }
        
        if ids.count != raw.count { return "ids must all be strings" }
        
        let cutoff = context.now - Activation.usedLookbackSec
        let label = context.sessionId
        let surfaced = try scope.run(
            NotesSurfacedRecentlyTransaction(noteIds: ids, cutoff: cutoff, label: label)
        )
        
        if let missing = ids.first(where: { id in !surfaced.contains(id) }) {
            return "note '\(missing)' was not surfaced in any recent activity window"
                + ((label?.isEmpty == false) ? " of session '\(label!)'" : "")
                + " (lookback \(Activation.usedLookbackSec)s) — cannot mark unobserved usage"
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let ids = (op["ids"] as! [Any]).compactMap { value in value as? String }
        
        // Fresh retrieval events may not be succeeded into hits yet —
        // derive first so validation's union judgement (hits ∪ pending
        // events) and the marking below see the same universe. The
        // notSurfaced throw inside is a backstop, not a second gate: it
        // shares the context's now/session with validation.
        _ = try scope.run(DeriveActivityWindowsTransaction(now: context.now))
        
        let outcomes = try scope.run(MarkNotesUsedTransaction(
            ids: ids,
            response: op["response"] as? String,
            sessionLabel: context.sessionId,
            now: context.now
        ))
        let marked = outcomes.filter { outcome in outcome.matched }
        let failed = outcomes.filter { outcome in !outcome.matched }
        var note = "marked \(marked.count) note(s) used"
        
        if let first = marked.first { note += " (signal: \(first.signal))" }
        
        if !failed.isEmpty {
            let names = failed.map { outcome in outcome.noteId }.joined(separator: ", ")
            note += "; overlap check failed for: \(names)"
        }
        
        return ["status": "ok", "ids": marked.map { outcome in outcome.noteId }, "note": note]
    }
    
    // MARK: - Private
}
