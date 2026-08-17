//
//  FlagHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct FlagHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "attach a maintenance flag to a note (no file edit). re-flagging same kind increments flag_count + bumps last_flagged_at + clears resolved_at.",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("kind", "one of: reconsolidate | stale_ref"),
            .required("reason", "human-readable rationale for the flag")
        ],
        example: ##"{"op":"flag","id":"my-note","kind":"reconsolidate","reason":"two near-duplicate notes detected"}"##
    )
    
    private let noteExistence = NoteExistence()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> String? {
        let kind = op["kind"] as? String ?? ""
        
        if !OperationVocabulary.creatableFlagKinds.contains(kind) { return "invalid flag kind: \(kind)" }
        
        return try noteExistence.rejectionForUnknown(op["id"] as? String ?? "", context: context, db: db)
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any] {
        let now = context.now
        
        try AddRippleFlagOperation(
            noteId: op["id"] as! String,
            kind: op["kind"] as! String,
            reason: op["reason"] as? String ?? "",
            now: now
        ).execute(db)
        
        return ["status": "ok", "ids": [op["id"]!], "note": "flagged \(op["kind"]!)"]
    }
    
    // MARK: - Private
}
