//
//  DeleteNoteHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct DeleteNoteHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "soft-delete a note: file moves to cortex/.trash/, DB row removed; refuses if deliberate inbound links exist (reference/lineage — learned cooccur/assoc do not block)",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("reason", "why deleting; recorded in trashed frontmatter (≤200 chars)"),
            .optional("force", "boolean; if true, bypasses the deliberate-inbound-link check")
        ],
        example: ##"{"op":"delete_note","id":"obsolete","reason":"merged into newer-note"}"##
    )
    
    private let noteExistence = NoteExistence()
    
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> String? {
        let noteId = op["id"] as? String ?? ""
        
        if let rejection = try noteExistence.rejectionForUnknown(noteId, context: context, db: db) {
            return rejection
        }
        
        if (op["force"] as? Bool) == true { return nil }
        
        let inbound = try db.run(FetchInboundBlockersTransaction(noteId: noteId))
        
        if !inbound.isEmpty {
            return "inbound links exist (src: \(inbound.joined(separator: ", "))) — resolve them or set force=true"
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any] {
        let noteId = op["id"] as! String
        let now = context.now
        
        guard let src = try context.brain.notePath(db, noteId) else {
            throw OperationError.unknownNote(noteId)
        }
        
        try db.run(RemoveNoteRowsTransaction(
            nid: noteId,
            flagReason: "deleted \(noteId)",
            now: now
        ))
        
        // Safe to move here: `touches` names both this file and its trash
        // destination, so a rollback of the surrounding batch restores them.
        let trashPath = try Trash(layout: context.brain.layout).file(src, reason: op["reason"] as? String ?? "", now: now)
        
        let reasonShort = (op["reason"] as? String ?? "").unicodeScalarPrefix(80)
        
        return [
            "status": "ok",
            "ids": [noteId],
            "path": (trashPath ?? src).path,
            "note": "deleted (backup at .trash/, reason: \(reasonShort))"
        ]
    }
    
    func effect(_ op: [String: Any]) -> [String: [String]] {
        ["removes": [op["id"] as? String ?? ""]]
    }
    
    func touches(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [URL] {
        guard let noteId = op["id"] as? String,
            let src = try context.brain.notePath(db, noteId)
        else {
            return []
        }
        
        return Trash(layout: context.brain.layout).destination(of: src).map { destination in [src, destination] } ?? [src]
    }
    
    // MARK: - Private
}
