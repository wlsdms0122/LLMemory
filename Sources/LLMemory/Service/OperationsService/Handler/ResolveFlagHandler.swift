//
//  ResolveFlagHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct ResolveFlagHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "mark a ripple_flag as resolved (sets resolved_at). idempotent — already-resolved flags are no-op.",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("kind", "flag kind to resolve (reconsolidate / stale_ref / enrich_review)"),
            .optional("reason", "what changed to resolve it (recorded in note_lifecycle_events)")
        ],
        example: ##"{"op":"resolve_flag","id":"my-note","kind":"reconsolidate","reason":"merged with sibling"}"##
    )
    
    private let noteExistence = NoteExistence()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let kind = op["kind"] as? String ?? ""
        
        if !OpVocabulary.resolvableFlagKinds.contains(kind) { return "invalid flag kind: \(kind)" }
        
        return try noteExistence.rejectionForUnknown(op["id"] as? String ?? "", context: context, scope: scope)
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let now = context.now
        let resolved = try scope.run(ResolveRippleFlagTransaction(
            noteId: op["id"] as! String,
            kind: op["kind"] as! String,
            reason: op["reason"] as? String,
            now: now
        ))
        
        return [
            "status": "ok",
            "ids": [op["id"]!],
            "note": resolved > 0
                ? "resolved \(op["kind"]!)"
                : "no unresolved flag of kind \(op["kind"]!)"
        ]
    }
    
    // MARK: - Private
}
