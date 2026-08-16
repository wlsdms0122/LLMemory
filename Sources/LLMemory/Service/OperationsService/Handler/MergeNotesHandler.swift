//
//  MergeNotesHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct MergeNotesHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "merge several notes into one (existing) target; from_ids are deleted, links redirected",
        fields: [
            .required("into_id", role: .noteId, "target note id; must exist (pre-create with create_note in the same txn for fresh umbrella)"),
            .required("from_ids", role: .noteIdList, "non-empty list of note ids to merge in; must not include into_id"),
            .required("merged_content", "full body for the merged note (replaces target body)"),
            .required("summary", "new summary for the merged note"),
            .required("tags", "non-empty tag list for the merged note"),
            .optional("title", "override title; defaults to existing or into_id"),
            .optional("priority", "'eager' | 'lazy'"),
            .optional("source", "string or list of source refs. Local absolute paths are drift-tracked; URLs/dates/relative refs kept as provenance only.")
        ],
        example: ##"{"op":"merge_notes","into_id":"umbrella","from_ids":["a","b"],"merged_content":"...","summary":"...","tags":["persona"]}"##
    )
    
    private let noteExistence = NoteExistence()
    private let sourceInput = NoteSourceInput()
    
    private let frontmatter = Frontmatter()
    
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let intoId = op["into_id"] as? String ?? ""
        
        if let rejection = try noteExistence.rejectionForUnknown(intoId, context: context, scope: scope) {
            return "merge_notes.into_id must be an *existing* note id (or one created earlier in this transaction): '\(intoId)'. To merge into a fresh umbrella note, prepend a `create_note` op with the same id, then merge. (\(rejection))"
        }
        
        guard let fromIds = op["from_ids"] as? [Any], !fromIds.isEmpty else {
            return "from_ids must be non-empty list"
        }
        
        let fromStrings = fromIds.compactMap { id in id as? String }
        
        if fromStrings.contains(intoId) {
            return "into_id cannot also be in from_ids: \(intoId)"
        }
        
        for fromId in fromStrings {
            if let rejection = try noteExistence.rejectionForUnknown(fromId, context: context, scope: scope) {
                return "from_ids: \(rejection)"
            }
        }
        
        guard let tags = op["tags"] as? [Any], !tags.isEmpty else {
            return "tags must be non-empty list"
        }
        
        if let rejection = sourceInput.sourceInputError(op["source"]) { return rejection }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let intoId = op["into_id"] as! String
        let fromIds = (op["from_ids"] as? [Any])?.compactMap { id in id as? String } ?? []
        
        guard let intoPath = try scope.run(FetchNotePathTransaction(nid: intoId)),
            FileManager.default.fileExists(atPath: intoPath.path)
        else {
            throw OperationError.noteFileMissing(op: "merge_notes", id: intoId)
        }
        
        var (intoDoc, _) = try frontmatter.parse(
            try String(contentsOf: intoPath, encoding: .utf8)
        )
        intoDoc.title = (op["title"] as? String)
            ?? (intoDoc.title.isEmpty ? intoId : intoDoc.title)
        intoDoc.tags = (op["tags"] as? [Any])?.compactMap { tag in tag as? String }
            ?? intoDoc.tags
        intoDoc.summary = (op["summary"] as? String) ?? intoDoc.summary
        
        if let priority = op["priority"] as? String { intoDoc.priority = priority }
        
        if op["source"] != nil {
            intoDoc.source = try sourceInput.finalizeSource(op["source"])
        }
        
        let rawMerged = op["merged_content"] as? String ?? ""
        let merged = String(
            rawMerged.reversed().drop(while: { character in character.isWhitespace }).reversed()
        )
        let body = merged + "\n"
        var fromPaths: [URL] = []
        
        for fromId in fromIds {
            if let path = try scope.run(FetchNotePathTransaction(nid: fromId)),
                FileManager.default.fileExists(atPath: path.path) {
                fromPaths.append(path)
            }
        }
        
        let now = context.now
        
        try (frontmatter.dump(intoDoc) + body).write(
            to: intoPath,
            atomically: true,
            encoding: .utf8
        )
        try scope.run(ReindexNoteFileTransaction(path: intoPath))
        try scope.run(StampNoteLifecycleTransaction(nid: intoId, now: now, isNew: false))
        
        for fromId in fromIds {
            _ = try scope.run(FlagInboundReferrersTransaction(
                targetId: fromId,
                reason: "merged into \(intoId)",
                now: now
            ))
            try scope.run(RedirectLinksForMergeTransaction(fromId: fromId, intoId: intoId))
            try scope.run(AbsorbNoteArtifactsForMergeTransaction(from: fromId, into: intoId))
            try scope.run(DeleteNoteRowTransaction(nid: fromId))
        }
        
        try scope.run(SyncNoteEnrichTransaction(noteId: intoId))
        
        for path in fromPaths {
            try Trash(paths: scope.brain.paths).file(path, reason: "merged into \(intoId)", now: now)
        }
        
        return [
            "status": "ok",
            "path": intoPath.path,
            "ids": [intoId],
            "note": "merged \(fromIds.count) into \(intoId)"
        ]
    }
    
    func effect(_ op: [String: Any]) -> [String: [String]] {
        let fromIds = (op["from_ids"] as? [Any])?.compactMap { id in id as? String } ?? []
        
        return ["removes": fromIds]
    }
    
    func touches(_ op: [String: Any], _ scope: GRDBReadScope) throws -> [URL] {
        var paths: [URL] = []
        
        if let intoId = op["into_id"] as? String, let path = try scope.run(FetchNotePathTransaction(nid: intoId)) {
            paths.append(path)
        }
        
        let fromIds = (op["from_ids"] as? [Any])?.compactMap { id in id as? String } ?? []
        
        for fromId in fromIds {
            if let path = try scope.run(FetchNotePathTransaction(nid: fromId)) {
                paths.append(path)
                
                if let trashPath = Trash(paths: scope.brain.paths).destination(of: path) { paths.append(trashPath) }
            }
        }
        
        return paths
    }
    
    // MARK: - Private
}
