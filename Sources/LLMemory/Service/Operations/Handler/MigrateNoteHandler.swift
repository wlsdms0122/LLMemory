//
//  MigrateNoteHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

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
        _ scope: GRDBReadScope
    ) throws -> String? {
        let noteId = op["id"] as? String ?? ""
        
        if let rejection = try noteExistence.rejectionForUnknown(noteId, context: context, scope: scope) {
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
        
        if newId != noteId, try noteExistence.isTaken(newId, context: context, scope: scope) {
            return "new_id collision: \(newId)"
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let targetId = op["id"] as! String
        let newId = (op["new_id"] as? String) ?? targetId
        let newPath = context.brain.layout.file(forId: newId)
        
        guard let srcPath = try context.brain.notePath(scope, targetId),
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
            ? try scope.run(FetchNoteEntityHitsTransaction(noteId: targetId))
            : []
        
        try scope.run(ReindexNoteFileTransaction(noteId: try context.brain.requireNoteId(of: newPath), path: newPath))
        
        var rewritten: [String] = []
        
        if newId != targetId {
            try scope.run(ReparentNoteArtifactsTransaction(from: targetId, to: newId))
            try scope.run(DeleteNoteRowTransaction(nid: targetId))
            try scope.run(ClearNoteTagsTransaction(noteId: targetId))
            
            for hit in oldEntityHits {
                try scope.run(SetEntityHitCountTransaction(noteId: newId, entity: hit.entity, hits: hit.hits))
            }
            
            try scope.run(SyncNoteEnrichTransaction(noteId: newId))
            try scope.run(NormalizeUndirectedLinksTransaction(nodeId: newId))
            
            // After the new id exists, so the rewritten citations resolve
            // to it on reindex rather than dangling for an instant.
            rewritten = try citationRewriter.rewrite(scope, context.brain, from: targetId, to: newId)
        }
        
        try scope.run(StampNoteLifecycleTransaction(nid: newId, file: context.brain.layout.file(forId: newId), now: now, isNew: false))
        
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
        _ scope: GRDBReadScope
    ) throws -> [URL] {
        var paths: [URL] = []
        
        if let noteId = op["id"] as? String, let src = try context.brain.notePath(scope, noteId) {
            paths.append(src)
        }
        
        guard let targetId = op["id"] as? String else { return paths }
        
        paths.append(context.brain.layout.file(forId: (op["new_id"] as? String) ?? targetId))
        
        // The notes that cite this id are rewritten by the write, so they
        // belong in the snapshot — a rollback has to put them back.
        for src in try scope.run(FetchCitingNoteIdsTransaction(marker: targetId)) {
            paths.append(context.brain.layout.file(forId: src))
        }
        
        return paths
    }
    
    // MARK: - Private
}
