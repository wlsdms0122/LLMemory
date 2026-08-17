//
//  SetFrontmatterHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct SetFrontmatterHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "merge frontmatter fields (any field the note owns)",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("fields", "non-empty dict. Known: title|summary|tags|priority|source|promoted_from|entities. Any other key is a custom field (scalar value, projected to note_extra); null removes it. Rejected: id/template/locked/stale/invalidated_*/trashed_* — each has its own op")
        ],
        example: ##"{"op":"set_frontmatter","id":"my-note","fields":{"summary":"updated summary","affect":"high"}}"##
    )
    
    private let composer = NoteComposer()
    private let noteExistence = NoteExistence()
    private let bookkeeper = NoteWriteBookkeeper()
    
    private let frontmatter = Frontmatter()
    
    private let noteFile = NoteFile()
    
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
        
        guard let fields = op["fields"] as? [String: Any], !fields.isEmpty else {
            return "fields must be non-empty dict"
        }
        
        if let tags = fields["tags"] {
            guard let array = tags as? [Any], !array.isEmpty else {
                return "tags must be non-empty list"
            }
        }
        
        if let priority = fields["priority"] as? String,
            !OperationVocabulary.validPriority.contains(priority) {
            return "invalid priority: \(priority)"
        }
        
        do {
            var probe = FrontmatterDocument()
            
            if let path = try context.brain.notePath(db, noteId),
                let read = try noteFile.readNoteIfPresent(at: path) {
                probe = read.doc
            }
            
            try composer.mergeFields(&probe, fields)
        } catch {
            return "\(error)"
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any] {
        let noteId = op["id"] as! String
        
        guard let path = try context.brain.notePath(db, noteId),
            FileManager.default.fileExists(atPath: path.path)
        else {
            throw OperationError.noteFileMissing(op: "set_frontmatter", id: noteId)
        }
        
        let raw = try String(contentsOf: path, encoding: .utf8)
        var (doc, body) = try frontmatter.parse(raw)
        let fields = op["fields"] as! [String: Any]
        
        try composer.mergeFields(&doc, fields)
        try (frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
        try db.run(ReindexNoteFileTransaction(noteId: try context.brain.requireNoteId(of: path), path: path))
        
        let now = context.now
        
        try db.run(StampNoteLifecycleTransaction(nid: noteId, file: context.brain.layout.file(forId: noteId), now: now, isNew: false))
        
        let keys = fields.keys.sorted().joined(separator: ",")
        
        try bookkeeper.recordEdit(db, nid: noteId, opLabel: "set_frontmatter/\(keys)", now: now)
        
        return [
            "status": "ok",
            "path": path.path,
            "ids": [noteId],
            "note": "updated fields: \(fields.keys.sorted())"
        ]
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
