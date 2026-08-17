//
//  MigrateNoteHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct MigrateNoteHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "re-address a note — the file relocates to match the new id and every citation of the old id is rewritten",
        fields: [
            .required("id", role: .noteId, "current note id"),
            .required("new_id", role: .noteId, "new id — dot-joined labels; the file moves to match")
        ],
        example: ##"{"op":"migrate_note","id":"flow.my-note","new_id":"flow.review.my-note"}"##
    )
    
    private let noteExistence = NoteExistence()
    
    private let frontmatter = Frontmatter()
    
    private let citationRewriter = CitationRewriter()
    
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
        
        let newId = (op["new_id"] as? String) ?? noteId
        let nsNewId = newId as NSString
        
        if NoteAddress.idRegex.firstMatch(
            in: newId,
            range: NSRange(location: 0, length: nsNewId.length)
        ) == nil {
            return "invalid new_id format: \(newId)"
        }
        
        if newId != noteId, try noteExistence.isTaken(newId, context: context, db: db) {
            return "new_id collision: \(newId)"
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any] {
        let targetId = op["id"] as! String
        let newId = (op["new_id"] as? String) ?? targetId
        let newPath = context.brain.layout.file(forId: newId)
        
        guard let srcPath = try context.brain.notePath(db, targetId),
            FileManager.default.fileExists(atPath: srcPath.path)
        else {
            throw OperationError.noteFileMissing(op: "migrate_note", id: targetId)
        }
        
        let (doc, body) = try frontmatter.parse(try String(contentsOf: srcPath, encoding: .utf8))
        
        try FileManager.default.createDirectory(
            at: newPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        let now = context.now
        
        try (frontmatter.dump(doc) + body).write(to: newPath, atomically: true, encoding: .utf8)
        
        if newPath != srcPath {
            try FileManager.default.removeItem(at: srcPath)
        }
        
        let oldEntityHits: [(entity: String, hits: Int)] = (newId != targetId)
            ? try FetchNoteEntityHitsOperation(noteId: targetId).execute(db)
            : []
        
        try ReindexNoteFileOperation(noteId: try context.brain.requireNoteId(of: newPath), path: newPath).execute(db)
        
        var rewritten: [String] = []
        
        if newId != targetId {
            try ReparentNoteArtifactsOperation(from: targetId, to: newId).execute(db)
            try DeleteNoteRowOperation(nid: targetId).execute(db)
            try ClearNoteTagsOperation(noteId: targetId).execute(db)
            
            for hit in oldEntityHits {
                try SetEntityHitCountOperation(noteId: newId, entity: hit.entity, hits: hit.hits).execute(db)
            }
            
            try SyncNoteEnrichOperation(noteId: newId).execute(db)
            try NormalizeUndirectedLinksOperation(nodeId: newId).execute(db)
            
            // After the new id exists, so the rewritten citations resolve
            // to it on reindex rather than dangling for an instant.
            rewritten = try citationRewriter.rewrite(db, context.brain, from: targetId, to: newId)
        }
        
        try StampNoteLifecycleOperation(nid: newId, file: context.brain.layout.file(forId: newId), now: now, isNew: false).execute(db)
        
        let citations = rewritten.isEmpty
            ? ""
            : " (\(rewritten.count) citing note\(rewritten.count == 1 ? "" : "s") rewritten)"
        
        return [
            "status": "ok",
            "path": newPath.path,
            "ids": [newId] + rewritten,
            "note": "migrated \(targetId) -> \(newId)\(citations)"
        ]
    }
    
    func effect(_ op: [String: Any]) -> [String: [String]] {
        let newId = (op["new_id"] as? String) ?? (op["id"] as? String ?? "")
        let id = op["id"] as? String ?? ""
        
        if newId != id {
            return ["creates": [newId], "removes": [id]]
        }
        
        return [:]
    }
    
    func touches(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [URL] {
        var paths: [URL] = []
        
        if let noteId = op["id"] as? String, let src = try context.brain.notePath(db, noteId) {
            paths.append(src)
        }
        
        guard let targetId = op["id"] as? String else { return paths }
        
        paths.append(context.brain.layout.file(forId: (op["new_id"] as? String) ?? targetId))
        
        // The notes that cite this id are rewritten by the write, so they
        // belong in the snapshot — a rollback has to put them back.
        for src in try FetchCitingNoteIdsOperation(marker: targetId).execute(db) {
            paths.append(context.brain.layout.file(forId: src))
        }
        
        return paths
    }
    
    // MARK: - Private
}
