//
//  InvalidateHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct InvalidateHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "mark a note stale (frontmatter + DB) and ripple-flag inbound links",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("reason", "why this note is stale; recorded in frontmatter + lifecycle")
        ],
        example: ##"{"op":"invalidate","id":"my-note","reason":"superseded by newer source"}"##
    )
    
    private let noteExistence = NoteExistence()
    
    private let frontmatter = Frontmatter()
    
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
        
        let priority = try db.run(FetchNotePriorityTransaction(nid: noteId))
        
        if priority == "eager" { return "cannot invalidate eager note: \(noteId)" }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any] {
        let now = context.now
        let noteId = op["id"] as! String
        
        guard let path = try context.brain.notePath(db, noteId),
            FileManager.default.fileExists(atPath: path.path)
        else {
            throw OperationError.noteFileMissing(op: "invalidate", id: noteId)
        }
        
        var (doc, body) = try frontmatter.parse(try String(contentsOf: path, encoding: .utf8))
        doc.stale = true
        doc.invalidatedAt = now
        
        if let reason = op["reason"] as? String, !reason.isEmpty {
            doc.invalidatedReason = reason.unicodeScalarPrefix(200)
        }
        
        try (frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
        try db.run(ReindexNoteFileTransaction(noteId: try context.brain.requireNoteId(of: path), path: path))
        try db.run(SetNoteStaleTransaction(nid: noteId, stale: true))
        try db.run(RecordNoteLifecycleEventTransaction(nid: noteId,
            kind: "invalidated",
            reason: op["reason"] as? String,
            now: now
        ))
        
        let reasonShort = (op["reason"] as? String ?? "").unicodeScalarPrefix(100)
        
        _ = try db.run(FlagInboundReferrersTransaction(
            targetId: noteId,
            reason: "invalidated: \(reasonShort)",
            now: now
        ))
        
        return ["status": "ok", "path": path.path, "ids": [noteId], "note": "invalidated"]
    }
    
    func effect(_ op: [String: Any]) -> [String: [String]] {
        ["invalidates": [op["id"] as? String ?? ""]]
    }
    
    func touches(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [URL] {
        guard let noteId = op["id"] as? String,
            let path = try context.brain.notePath(db, noteId)
        else {
            return []
        }
        
        return [path]
    }
    
    // MARK: - Private
}
