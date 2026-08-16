//
//  RenameSectionHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct RenameSectionHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "rename a section heading in place (level preserved)",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("section", ###"section path with heading marker, e.g. "## 옛제목""###),
            .required("new_title", "new heading text (no marker — level is preserved)")
        ],
        example: ###"{"op":"rename_section","id":"my-note","section":"## 옛제목","new_title":"새제목"}"###
    )
    
    private let noteExistence = NoteExistence()
    private let writeEffects = NoteWriteBookkeeper()
    
    private let sectionEdit = SectionEdit()
    
    private let frontmatter = Frontmatter()
    
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
        
        do {
            _ = try sectionEdit.parsePath(op["section"] as? String ?? "")
        } catch {
            return "invalid section path: \(error)"
        }
        
        return nil
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let noteId = op["id"] as! String
        
        guard let path = try scope.run(FetchNotePathTransaction(nid: noteId)),
            FileManager.default.fileExists(atPath: path.path)
        else {
            throw OperationError.noteFileMissing(op: "rename_section", id: noteId)
        }
        
        let raw = try String(contentsOf: path, encoding: .utf8)
        let (doc, body) = try frontmatter.parse(raw)
        let sectionPath = try sectionEdit.parsePath(op["section"] as! String)
        let newTitle = op["new_title"] as! String
        let newBody = try sectionEdit.rename(body, path: sectionPath, newTitle: newTitle)
        
        try (frontmatter.dump(doc) + newBody).write(to: path, atomically: true, encoding: .utf8)
        try scope.run(ReindexNoteFileTransaction(path: path))
        
        let now = context.now
        
        try scope.run(StampNoteLifecycleTransaction(nid: noteId, now: now, isNew: false))
        try writeEffects.recordEdit(scope, nid: noteId, opLabel: "rename_section", now: now)
        
        return [
            "status": "ok",
            "path": path.path,
            "ids": [noteId],
            "note": "renamed: \(newTitle)"
        ]
    }
    
    func touches(_ op: [String: Any], _ scope: GRDBReadScope) throws -> [URL] {
        guard let noteId = op["id"] as? String,
            let path = try scope.run(FetchNotePathTransaction(nid: noteId))
        else {
            return []
        }
        
        return [path]
    }
    
    // MARK: - Private
}
