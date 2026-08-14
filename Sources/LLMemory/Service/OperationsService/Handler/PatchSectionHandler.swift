//
//  PatchSectionHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct PatchSectionHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "section-level surgical edit (replace/append/prepend/remove)",
        fields: [
            .required("id", role: .noteId, "target note id"),
            .required("section", ###"section path with heading marker, e.g. "## 제목" or "## A > ### B" (level must strictly increase across ' > '). Use "(preamble)" to target the body before the first heading (the whole body when heading-free — e.g. an index/pointer note)."###),
            .required("action", "one of: replace | append | prepend | remove"),
            .optional("content", "body text; required for all actions except 'remove'. For 'replace': body only — must NOT start with a heading at level ≤ leaf"),
            .optional("subtree", ###"bool, default false. 'replace': false 면 직속 본문만 교체하고 하위 섹션 보존, true 면 서브트리 전체 교체. 'append': false 면 직속 본문 끝(첫 자식 heading 앞)에 삽입, true 면 서브트리 끝(마지막 자식 뒤)에 삽입. 'remove': 대상에 하위 섹션이 있으면 false 는 거부(동반 삭제 방지), true 면 서브트리째 삭제."###)
        ],
        example: ###"{"op":"patch_section","id":"my-note","section":"## 관련","action":"append","content":"- 새 항목"}"###
    )
    
    private let noteExistence = NoteExistence()
    private let writeEffects = NoteWriteEffects()
    
    private let sectionEdit = SectionEdit()
    
    private let frontmatter = Frontmatter()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let action = op["action"] as? String ?? ""
        
        if !OpVocabulary.validPatchActions.contains(action) {
            return "invalid action: \(action) (expected \(OpVocabulary.validPatchActions.sorted()))"
        }
        
        if action != "remove" && (op["content"] as? String ?? "").isEmpty {
            return "content required for action=\(action)"
        }
        
        let noteId = op["id"] as? String ?? ""
        
        if let rejection = try noteExistence.rejectionForUnknown(noteId, context: context, scope: scope) {
            return rejection
        }
        
        if (op["section"] as? String) == SectionEdit.preambleToken { return nil }
        
        let sectionPath: SectionEdit.SectionPath
        do {
            sectionPath = try sectionEdit.parsePath(op["section"] as? String ?? "")
        } catch {
            return "invalid section path: \(error)"
        }
        
        if action == "replace" {
            let leafLevel = sectionPath.parts.last?.level ?? 1
            let content = op["content"] as? String ?? ""
            
            for line in content.components(separatedBy: "\n") {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                
                let nsLine = line as NSString
                
                if let match = OpVocabulary.headingMarkerRegex.firstMatch(
                    in: line,
                    range: NSRange(location: 0, length: nsLine.length)
                ) {
                    let hashes = nsLine.substring(with: match.range(at: 1))
                    let title = nsLine.substring(with: match.range(at: 2))
                    
                    if hashes.count <= leafLevel {
                        let truncated = String(title.prefix(40))
                        
                        return "replace preserves the existing heading; content must not start with a heading at level ≤ \(leafLevel). pass section body only (drop the leading '\(hashes) \(truncated)' line)"
                    }
                }
                
                break
            }
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
            throw OperationError.noteFileMissing("note file missing: \(noteId)")
        }
        
        let raw = try String(contentsOf: path, encoding: .utf8)
        let (doc, body) = try frontmatter.parse(raw)
        let section = op["section"] as! String
        let action = op["action"] as! String
        let content = op["content"] as? String ?? ""
        let subtree = op["subtree"] as? Bool ?? false
        let newBody = try sectionEdit.applyPatch(
            body,
            section: section,
            action: action,
            content: content,
            subtree: subtree
        )
        
        try (frontmatter.dump(doc) + newBody).write(to: path, atomically: true, encoding: .utf8)
        try scope.run(ReindexNoteFileTransaction(path: path))
        
        let now = context.now
        
        try scope.run(StampNoteLifecycleTransaction(nid: noteId, now: now, isNew: false))
        try writeEffects.recordEdit(
            scope,
            nid: noteId,
            opLabel: "patch_section/\(action)",
            now: now
        )
        
        let isSubtreeAction = action == "replace" || action == "remove" || action == "append"
        let noteSuffix = (subtree && isSubtreeAction) ? " (subtree)" : ""
        
        return [
            "status": "ok",
            "path": path.path,
            "ids": [noteId],
            "note": "patch_section action=\(action)\(noteSuffix)"
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
