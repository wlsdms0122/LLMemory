//
//  RestoreHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct RestoreHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "restore a trashed note (cortex/.trash/) back to its address with a fresh DB row",
        fields: [
            .required("id", role: .noteId, "target note id; must exist in cortex/.trash/"),
            .optional("reason", "lifecycle event reason recorded on restore")
        ],
        example: ##"{"op":"restore","id":"deleted-note","reason":"deleted by mistake"}"##
    )
    
    private let noteExistence = NoteExistence()
    private let trashLookup = TrashedNoteLookup()
    
    private let frontmatter = Frontmatter()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let noteId = op["id"] as? String ?? ""
        let state = try noteExistence.state(scope)
        
        if state.ids.contains(noteId) || context.inFlightIds.contains(noteId) {
            return "id collision: '\(noteId)' is already a live note — restoring would overwrite it"
        }
        
        do {
            if try trashLookup.findTrashedFile(noteId) != nil { return nil }
        } catch {
            return "\(error)"
        }
        
        return "not in trash: \(noteId)"
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let noteId = op["id"] as! String
        let now = context.now
        
        guard let found = try trashLookup.findTrashedFile(noteId) else {
            throw OperationError.notInTrash(noteId)
        }
        
        let trashFile = found.url
        var doc = found.doc
        let body = found.body
        
        doc.trashedAt = nil
        doc.trashedReason = nil
        
        let destination = Paths.file(forId: noteId)
        
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (frontmatter.dump(doc) + body).write(
            to: destination,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.removeItem(at: trashFile)
        try scope.run(ReindexNoteFileTransaction(path: destination))
        try scope.run(TouchNoteUsageTransaction(noteId: noteId, now: now))
        try scope.run(RecordNoteLifecycleEventTransaction(nid: noteId,
            kind: "restored",
            reason: op["reason"] as? String,
            now: now
        ))
        
        return [
            "status": "ok",
            "path": destination.path,
            "ids": [noteId],
            "note": "restored from trash (fresh DB row)"
        ]
    }
    
    func effect(_ op: [String: Any]) -> [String: [String]] {
        ["creates": [op["id"] as? String ?? ""]]
    }
    
    func touches(_ op: [String: Any], _ scope: GRDBReadScope) throws -> [URL] {
        let noteId = op["id"] as? String ?? ""
        
        guard let found = try trashLookup.findTrashedFile(noteId) else { return [] }
        
        return [found.url, Paths.file(forId: noteId)]
    }
    
    // MARK: - Private
}
