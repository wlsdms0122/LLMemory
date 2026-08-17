//
//  CreateNoteHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation
import GRDB

struct CreateNoteHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "create a new note (file + DB row)",
        fields: [
            .required("id", role: .noteId, "the note's address — dot-joined lowercase labels ([a-z0-9-]); `a.b.c` puts the file at cortex/a/b/c.md. unique across active notes"),
            .required("title", "human-readable note title"),
            .required("tags", "non-empty string list — how the note is classified"),
            .required("summary", "one-line summary used by retrieval"),
            .required("content", unless: "template", "markdown body (frontmatter is generated). optional when 'template' is set — the template frame is scaffolded as empty sections"),
            .optional("priority", "'eager' | 'lazy' (default 'lazy'); eager has cap"),
            .optional("source", "string or list of source refs. Local absolute paths are drift-tracked (source_stale); URLs/dates/relative refs are kept as provenance only."),
            .optional("entities", "string list of named entities"),
            .optional("template", "id of a template note this note follows (structured document). body must conform to the template frame; empty content is scaffolded"),
            .optional("locked", "bool. true → human-only: subsequent operations mutation is refused, file is edited directly"),
            .optional("rationale", "lifecycle event reason recorded on creation")
        ],
        example: ##"{"op":"create_note","id":"persona.my-note","title":"...","tags":["persona"],"summary":"...","content":"# body"}"##
    )
    
    private let composer = NoteComposer()
    private let noteExistence = NoteExistence()
    private let sourceInput = NoteSourceInput()
    private let bookkeeper = NoteWriteBookkeeper()
    
    private let frontmatter = Frontmatter()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> String? {
        let hasTemplate = (op["template"] as? String).map { value in !value.isEmpty } ?? false
        
        if let rawLocked = op["locked"], !(rawLocked is Bool) { return "locked must be bool" }
        
        if hasTemplate {
            let templateId = op["template"] as! String
            
            if !(try db.run(NoteExistsTransaction(nid: templateId)))
                && !context.inFlightIds.contains(templateId) {
                return "unknown template note: \(templateId)"
            }
        }
        
        let noteId = op["id"] as? String ?? ""
        let nsNoteId = noteId as NSString
        
        if NoteAddress.idRegex.firstMatch(
            in: noteId,
            range: NSRange(location: 0, length: nsNoteId.length)
        ) == nil {
            return "invalid id format: \(noteId)"
        }
        
        guard let tags = op["tags"] as? [Any], !tags.isEmpty else {
            return "tags must be non-empty list"
        }
        
        let priority = op["priority"] as? String ?? "lazy"
        
        if !OperationVocabulary.validPriority.contains(priority) { return "invalid priority: \(priority)" }
        
        if let entities = op["entities"], !(entities is [Any]) { return "entities must be list" }
        
        if let rejection = sourceInput.sourceInputError(op["source"]) { return rejection }
        
        do {
            var probe = FrontmatterDocument()
            
            try composer.mergeFields(&probe, schema.undeclaredFields(in: op))
        } catch {
            return "\(error)"
        }
        
        if try noteExistence.isTaken(noteId, context: context, db: db) {
            return "id collision: \(noteId) (use patch_section to update)"
        }
        
        let path = context.brain.layout.file(forId: noteId)
        
        if FileManager.default.fileExists(atPath: path.path) {
            let relativePath = context.brain.layout.relative(of: path) ?? path.path
            
            return "path already exists: \(relativePath) (use patch_section)"
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [String: Any] {
        let now = context.now
        let noteId = op["id"] as! String
        let path = context.brain.layout.file(forId: noteId)
        
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        let body = try composer.composeCreateBody(op, db, context.brain)
        var doc = FrontmatterDocument(
            title: op["title"] as? String ?? "",
            priority: op["priority"] as? String ?? "lazy",
            summary: op["summary"] as? String ?? "",
            tags: (op["tags"] as? [Any])?.compactMap { tag in tag as? String } ?? []
        )
        doc.template = (op["template"] as? String).flatMap { value in
            value.isEmpty ? nil : value
        }
        
        if (op["locked"] as? Bool) == true { doc.locked = true }
        
        if op["source"] != nil {
            doc.source = try sourceInput.finalizeSource(op["source"])
        }
        
        let entities = (op["entities"] as? [Any])?
            .compactMap { entity in entity as? String }
            .filter { entity in !entity.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
        
        if !entities.isEmpty { doc.entities = entities }
        
        try composer.mergeFields(&doc, schema.undeclaredFields(in: op))
        try (frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
        
        try db.run(ReindexNoteFileTransaction(noteId: try context.brain.requireNoteId(of: path), path: path))
        try db.run(StampNoteLifecycleTransaction(nid: noteId, file: context.brain.layout.file(forId: noteId), now: now, isNew: true))
        try db.run(RecordNoteLifecycleEventTransaction(nid: noteId,
            kind: "created",
            reason: op["rationale"] as? String,
            now: now
        ))
        try bookkeeper.seedInitialLinks(db, nid: noteId, tags: doc.tags)
        
        return [
            "status": "ok",
            "path": path.path,
            "ids": [noteId],
            "note": "created at \(context.brain.layout.relativeFile(forId: noteId))"
        ]
    }
    
    func effect(_ op: [String: Any]) -> [String: [String]] {
        ["creates": [op["id"] as? String ?? ""]]
    }
    
    func touches(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ db: Database
    ) throws -> [URL] {
        (op["id"] as? String).map { id in [context.brain.layout.file(forId: id)] } ?? []
    }
    
    // MARK: - Private
}
