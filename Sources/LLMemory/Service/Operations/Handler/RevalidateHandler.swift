//
//  RevalidateHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct RevalidateHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "clear stale flag on a previously-invalidated note",
        fields: [
            .required("id", role: .noteId, "target note id; must currently be stale=true"),
            .required("reason", "why it's valid again; recorded in lifecycle")
        ],
        example: ##"{"op":"revalidate","id":"my-note","reason":"verified against current source"}"##
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
        
        guard let stale = try FetchNoteStaleStateOperation(nid: noteId).execute(db) else {
            return "unknown id: \(noteId)"
        }
        
        if !stale { return "note is not stale: \(noteId)" }
        
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
            throw OperationError.noteFileMissing(op: "revalidate", id: noteId)
        }
        
        var (doc, body) = try frontmatter.parse(try String(contentsOf: path, encoding: .utf8))
        doc.stale = false
        doc.invalidatedAt = nil
        doc.invalidatedReason = nil
        
        try (frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
        try ReindexNoteFileOperation(noteId: try context.brain.requireNoteId(of: path), path: path).execute(db)
        try SetNoteStaleOperation(nid: noteId, stale: false).execute(db)
        try RecordNoteLifecycleEventOperation(nid: noteId,
        kind: "revalidated",
        reason: op["reason"] as? String,
        now: now
        ).execute(db)
        
        return ["status": "ok", "path": path.path, "ids": [noteId], "note": "revalidated"]
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
