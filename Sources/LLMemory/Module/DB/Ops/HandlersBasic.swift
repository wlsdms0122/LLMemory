//
//  HandlersBasic.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation
import GRDB

public enum HandlersBasic {
    // MARK: - Property
    public static let createNote = OpHandler(
        schema: OpSchema(
            summary: "create a new note (file + DB row)",
            fields: [
                .required("axis", role: .axis, "axis name; must also appear in tags"),
                .required("id", role: .noteId, "lowercase + [a-z0-9-], unique across active notes"),
                .required("title", "human-readable note title"),
                .required("tags", "non-empty string list; must include axis"),
                .required("summary", "one-line summary used by retrieval"),
                .required("content", unless: "template", "markdown body (frontmatter is generated). optional when 'template' is set — the template frame is scaffolded as empty sections"),
                .optional("priority", "'eager' | 'lazy' (default 'lazy'); eager has cap"),
                .optional("source", "string or list of source refs. Local absolute paths are drift-tracked (source_stale); URLs/dates/relative refs are kept as provenance only."),
                .optional("entities", "string list of named entities"),
                .optional("template", "id of a template note this note follows (structured document). body must conform to the template frame; empty content is scaffolded"),
                .optional("locked", "bool. true → human-only: subsequent ops mutation is refused, file is edited directly"),
                .optional("axis_description", "required only when axis is brand new"),
                .optional("rationale", "lifecycle event reason recorded on creation")
            ],
            example: ##"{"op":"create_note","axis":"persona","id":"my-note","title":"...","tags":["persona"],"summary":"...","content":"# body"}"##
        ),
        validate: { op, context, db in
            let hasTemplate = (op["template"] as? String).map { value in !value.isEmpty } ?? false
            
            if let rawLocked = op["locked"], !(rawLocked is Bool) { return "locked must be bool" }
            
            if hasTemplate {
                let templateId = op["template"] as! String
                
                if !(try Notes.exists(db, nid: templateId))
                    && !context.inFlightIds.contains(templateId) {
                    return "unknown template note: \(templateId)"
                }
            }
            
            let noteId = op["id"] as? String ?? ""
            let nsNoteId = noteId as NSString
            
            if Handlers.idRegex.firstMatch(
                in: noteId,
                range: NSRange(location: 0, length: nsNoteId.length)
            ) == nil {
                return "invalid id format: \(noteId)"
            }
            
            guard let tags = op["tags"] as? [Any], !tags.isEmpty else {
                return "tags must be non-empty list"
            }
            
            let tagStrings = tags.compactMap { tag in tag as? String }
            
            guard let axis = op["axis"] as? String else { return "axis required" }
            
            if !tagStrings.contains(axis) { return "axis tag missing from tags: \(axis)" }
            
            let priority = op["priority"] as? String ?? "lazy"
            
            if !Handlers.validPriority.contains(priority) { return "invalid priority: \(priority)" }
            
            if let entities = op["entities"], !(entities is [Any]) { return "entities must be list" }
            
            if let rejection = Handlers.sourceInputError(op["source"]) { return rejection }
            
            let state = try Handlers.existingState(db)
            
            if state.ids.contains(noteId) || context.inFlightIds.contains(noteId) {
                return "id collision: \(noteId) (use patch_section to update)"
            }
            
            if !state.axes.contains(axis) && !context.inFlightAxes.contains(axis) {
                let nsAxis = axis as NSString
                
                if Handlers.axisRegex.firstMatch(
                    in: axis,
                    range: NSRange(location: 0, length: nsAxis.length)
                ) == nil {
                    return "invalid axis format: \(axis)"
                }
                
                if (op["axis_description"] as? String)?.isEmpty != false {
                    return "axis '\(axis)' is new — provide axis_description"
                }
            }
            
            let path = Handlers.pathFor(axis: axis, nid: noteId)
            
            if FileManager.default.fileExists(atPath: path.path) {
                let relativePath = Paths.relative(of: path) ?? path.path
                
                return "path already exists: \(relativePath) (use patch_section)"
            }
            
            return nil
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let axis = op["axis"] as! String
            let noteId = op["id"] as! String
            let path = Handlers.pathFor(axis: axis, nid: noteId)
            
            try FileManager.default.createDirectory(
                at: path.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            let body = try Handlers.composeCreateBody(op, db)
            var doc = FrontmatterDoc(
                id: noteId,
                title: op["title"] as? String ?? "",
                axis: axis,
                priority: op["priority"] as? String ?? "lazy",
                summary: op["summary"] as? String ?? "",
                tags: (op["tags"] as? [Any])?.compactMap { tag in tag as? String } ?? []
            )
            doc.template = (op["template"] as? String).flatMap { value in
                value.isEmpty ? nil : value
            }
            
            if (op["locked"] as? Bool) == true { doc.locked = true }
            
            if op["source"] != nil {
                doc.source = try Handlers.finalizeSource(op["source"])
            }
            
            let entities = (op["entities"] as? [Any])?
                .compactMap { entity in entity as? String }
                .filter { entity in !entity.trimmingCharacters(in: .whitespaces).isEmpty } ?? []
            
            if !entities.isEmpty { doc.entities = entities }
            
            try (Frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
            
            if let axisDescription = op["axis_description"] as? String, !axisDescription.isEmpty {
                try Vocab.ensureAxis(db, axis: axis, description: axisDescription, now: now)
            }
            
            try Notes.reindexFile(db, path: path)
            try Notes.stampLifecycle(db, nid: noteId, now: now, isNew: true)
            try Notes.recordLifecycleEvent(
                db,
                nid: noteId,
                kind: "created",
                reason: op["rationale"] as? String,
                now: now
            )
            try Handlers.seedInitialLinks(db, nid: noteId, tags: doc.tags)
            
            return [
                "status": "ok",
                "path": path.path,
                "ids": [noteId],
                "note": "created in axis \(axis)"
            ]
        },
        effect: { op in
            ["creates": [op["id"] as? String ?? ""]]
        },
        touches: { op, _ in
            [Handlers.pathFor(axis: op["axis"] as? String ?? "", nid: op["id"] as? String ?? "")]
        }
    )
    
    public static let patchSection = OpHandler(
        schema: OpSchema(
            summary: "section-level surgical edit (replace/append/prepend/remove)",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("section", ###"section path with heading marker, e.g. "## 제목" or "## A > ### B" (level must strictly increase across ' > '). Use "(preamble)" to target the body before the first heading (the whole body when heading-free — e.g. an index/pointer note)."###),
                .required("action", "one of: replace | append | prepend | remove"),
                .optional("content", "body text; required for all actions except 'remove'. For 'replace': body only — must NOT start with a heading at level ≤ leaf"),
                .optional("subtree", ###"bool, default false. 'replace': false 면 직속 본문만 교체하고 하위 섹션 보존, true 면 서브트리 전체 교체. 'append': false 면 직속 본문 끝(첫 자식 heading 앞)에 삽입, true 면 서브트리 끝(마지막 자식 뒤)에 삽입. 'remove': 대상에 하위 섹션이 있으면 false 는 거부(동반 삭제 방지), true 면 서브트리째 삭제."###)
            ],
            example: ###"{"op":"patch_section","id":"my-note","section":"## 관련","action":"append","content":"- 새 항목"}"###
        ),
        validate: { op, context, db in
            let action = op["action"] as? String ?? ""
            
            if !Handlers.validPatchActions.contains(action) {
                return "invalid action: \(action) (expected \(Handlers.validPatchActions.sorted()))"
            }
            
            if action != "remove" && (op["content"] as? String ?? "").isEmpty {
                return "content required for action=\(action)"
            }
            
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, db: db) {
                return rejection
            }
            
            if (op["section"] as? String) == SectionEdit.preambleToken { return nil }
            
            let sectionPath: SectionEdit.SectionPath
            do {
                sectionPath = try SectionEdit.parsePath(op["section"] as? String ?? "")
            } catch {
                return "invalid section path: \(error)"
            }
            
            if action == "replace" {
                let leafLevel = sectionPath.parts.last?.level ?? 1
                let content = op["content"] as? String ?? ""
                
                for line in content.components(separatedBy: "\n") {
                    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    
                    let nsLine = line as NSString
                    
                    if let match = Handlers.headingMarkerRegex.firstMatch(
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
        },
        write: { op, db in
            let noteId = op["id"] as! String
            
            guard let path = try Notes.pathOf(db, nid: noteId),
                FileManager.default.fileExists(atPath: path.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "note file missing: \(noteId)"
                ])
            }
            
            let raw = try String(contentsOf: path, encoding: .utf8)
            let (doc, body) = try Frontmatter.parse(raw)
            let section = op["section"] as! String
            let action = op["action"] as! String
            let content = op["content"] as? String ?? ""
            let subtree = op["subtree"] as? Bool ?? false
            let newBody = try SectionEdit.applyPatch(
                body,
                section: section,
                action: action,
                content: content,
                subtree: subtree
            )
            
            try (Frontmatter.dump(doc) + newBody).write(to: path, atomically: true, encoding: .utf8)
            try Notes.reindexFile(db, path: path)
            
            let now = Int(Date().timeIntervalSince1970)
            
            try Notes.stampLifecycle(db, nid: noteId, now: now, isNew: false)
            try Handlers.recordEdit(
                db,
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
        },
        effect: { _ in [:] },
        touches: { op, db in
            guard let noteId = op["id"] as? String,
                let path = try Notes.pathOf(db, nid: noteId)
            else {
                return []
            }
            
            return [path]
        }
    )
    
    public static let setFrontmatter = OpHandler(
        schema: OpSchema(
            summary: "merge frontmatter fields (mutable subset only)",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("fields", "non-empty dict of {title|summary|tags|priority|source|promoted_from: value}; tags must include axis if updated")
            ],
            example: ##"{"op":"set_frontmatter","id":"my-note","fields":{"summary":"updated summary","tags":["persona","new-tag"]}}"##
        ),
        validate: { op, context, db in
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, db: db) {
                return rejection
            }
            
            guard let fields = op["fields"] as? [String: Any], !fields.isEmpty else {
                return "fields must be non-empty dict"
            }
            
            let illegal = fields.keys.filter { key in
                !Handlers.frontmatterMutable.contains(key)
            }
            
            if !illegal.isEmpty {
                return "illegal fields: \(illegal.sorted()) (use rename_section/migrate_note/etc.; allowed=\(Handlers.frontmatterMutable.sorted()))"
            }
            
            if let tags = fields["tags"] {
                guard let array = tags as? [Any], !array.isEmpty else {
                    return "tags must be non-empty list"
                }
            }
            
            if let priority = fields["priority"] as? String,
                !Handlers.validPriority.contains(priority) {
                return "invalid priority: \(priority)"
            }
            
            do {
                var probe = FrontmatterDoc()
                
                if let path = try Notes.pathOf(db, nid: noteId),
                    let read = try Notes.readNoteIfPresent(at: path) {
                    probe = read.doc
                }
                
                try Handlers.mergeFields(&probe, fields)
            } catch {
                return "\(error)"
            }
            
            return nil
        },
        write: { op, db in
            let noteId = op["id"] as! String
            
            guard let path = try Notes.pathOf(db, nid: noteId),
                FileManager.default.fileExists(atPath: path.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "note file missing: \(noteId)"
                ])
            }
            
            let raw = try String(contentsOf: path, encoding: .utf8)
            var (doc, body) = try Frontmatter.parse(raw)
            let fields = op["fields"] as! [String: Any]
            
            try Handlers.mergeFields(&doc, fields)
            try (Frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
            try Notes.reindexFile(db, path: path)
            
            let now = Int(Date().timeIntervalSince1970)
            
            try Notes.stampLifecycle(db, nid: noteId, now: now, isNew: false)
            
            let keys = fields.keys.sorted().joined(separator: ",")
            
            try Handlers.recordEdit(db, nid: noteId, opLabel: "set_frontmatter/\(keys)", now: now)
            
            return [
                "status": "ok",
                "path": path.path,
                "ids": [noteId],
                "note": "updated fields: \(fields.keys.sorted())"
            ]
        },
        effect: { _ in [:] },
        touches: { op, db in
            guard let noteId = op["id"] as? String,
                let path = try Notes.pathOf(db, nid: noteId)
            else {
                return []
            }
            
            return [path]
        }
    )
    
    public static let renameSection = OpHandler(
        schema: OpSchema(
            summary: "rename a section heading in place (level preserved)",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("section", ###"section path with heading marker, e.g. "## 옛제목""###),
                .required("new_title", "new heading text (no marker — level is preserved)")
            ],
            example: ###"{"op":"rename_section","id":"my-note","section":"## 옛제목","new_title":"새제목"}"###
        ),
        validate: { op, context, db in
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, db: db) {
                return rejection
            }
            
            do {
                _ = try SectionEdit.parsePath(op["section"] as? String ?? "")
            } catch {
                return "invalid section path: \(error)"
            }
            
            return nil
        },
        write: { op, db in
            let noteId = op["id"] as! String
            
            guard let path = try Notes.pathOf(db, nid: noteId),
                FileManager.default.fileExists(atPath: path.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "note file missing: \(noteId)"
                ])
            }
            
            let raw = try String(contentsOf: path, encoding: .utf8)
            let (doc, body) = try Frontmatter.parse(raw)
            let sectionPath = try SectionEdit.parsePath(op["section"] as! String)
            let newTitle = op["new_title"] as! String
            let newBody = try SectionEdit.rename(body, path: sectionPath, newTitle: newTitle)
            
            try (Frontmatter.dump(doc) + newBody).write(to: path, atomically: true, encoding: .utf8)
            try Notes.reindexFile(db, path: path)
            
            let now = Int(Date().timeIntervalSince1970)
            
            try Notes.stampLifecycle(db, nid: noteId, now: now, isNew: false)
            try Handlers.recordEdit(db, nid: noteId, opLabel: "rename_section", now: now)
            
            return [
                "status": "ok",
                "path": path.path,
                "ids": [noteId],
                "note": "renamed: \(newTitle)"
            ]
        },
        effect: { _ in [:] },
        touches: { op, db in
            guard let noteId = op["id"] as? String,
                let path = try Notes.pathOf(db, nid: noteId)
            else {
                return []
            }
            
            return [path]
        }
    )
    
    public static let invalidate = OpHandler(
        schema: OpSchema(
            summary: "mark a note stale (frontmatter + DB) and ripple-flag inbound links",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("reason", "why this note is stale; recorded in frontmatter + lifecycle")
            ],
            example: ##"{"op":"invalidate","id":"my-note","reason":"superseded by newer source"}"##
        ),
        validate: { op, context, db in
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, db: db) {
                return rejection
            }
            
            let priority = try String.fetchOne(
                db,
                sql: "SELECT priority FROM notes WHERE id = ?",
                arguments: [noteId]
            )
            
            if priority == "eager" { return "cannot invalidate eager note: \(noteId)" }
            
            return nil
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let noteId = op["id"] as! String
            
            guard let path = try Notes.pathOf(db, nid: noteId),
                FileManager.default.fileExists(atPath: path.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "invalidate target missing: \(noteId)"
                ])
            }
            
            var (doc, body) = try Frontmatter.parse(try String(contentsOf: path, encoding: .utf8))
            doc.stale = true
            doc.invalidatedAt = now
            
            if let reason = op["reason"] as? String, !reason.isEmpty {
                doc.invalidatedReason = reason.unicodeScalarPrefix(200)
            }
            
            try (Frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
            try Notes.reindexFile(db, path: path)
            try Notes.setStale(db, nid: noteId, stale: true)
            try Notes.recordLifecycleEvent(
                db,
                nid: noteId,
                kind: "invalidated",
                reason: op["reason"] as? String,
                now: now
            )
            
            let reasonShort = (op["reason"] as? String ?? "").unicodeScalarPrefix(100)
            
            _ = try Ripple.flagInboundReferrers(
                db,
                targetId: noteId,
                reason: "invalidated: \(reasonShort)",
                now: now
            )
            
            return ["status": "ok", "path": path.path, "ids": [noteId], "note": "invalidated"]
        },
        effect: { op in ["invalidates": [op["id"] as? String ?? ""]] },
        touches: { op, db in
            guard let noteId = op["id"] as? String,
                let path = try Notes.pathOf(db, nid: noteId)
            else {
                return []
            }
            
            return [path]
        }
    )
    
    public static let revalidate = OpHandler(
        schema: OpSchema(
            summary: "clear stale flag on a previously-invalidated note",
            fields: [
                .required("id", role: .noteId, "target note id; must currently be stale=true"),
                .required("reason", "why it's valid again; recorded in lifecycle")
            ],
            example: ##"{"op":"revalidate","id":"my-note","reason":"verified against current source"}"##
        ),
        validate: { op, context, db in
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, db: db) {
                return rejection
            }
            
            let row = try Row.fetchOne(
                db,
                sql: "SELECT stale FROM notes WHERE id = ?",
                arguments: [noteId]
            )
            
            guard let row else { return "unknown id: \(noteId)" }
            
            let stale: Int = row["stale"] as Int? ?? 0
            
            if stale == 0 { return "note is not stale: \(noteId)" }
            
            return nil
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let noteId = op["id"] as! String
            
            guard let path = try Notes.pathOf(db, nid: noteId),
                FileManager.default.fileExists(atPath: path.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "revalidate target missing: \(noteId)"
                ])
            }
            
            var (doc, body) = try Frontmatter.parse(try String(contentsOf: path, encoding: .utf8))
            doc.stale = false
            doc.invalidatedAt = nil
            doc.invalidatedReason = nil
            
            try (Frontmatter.dump(doc) + body).write(to: path, atomically: true, encoding: .utf8)
            try Notes.reindexFile(db, path: path)
            try Notes.setStale(db, nid: noteId, stale: false)
            try Notes.recordLifecycleEvent(
                db,
                nid: noteId,
                kind: "revalidated",
                reason: op["reason"] as? String,
                now: now
            )
            
            return ["status": "ok", "path": path.path, "ids": [noteId], "note": "revalidated"]
        },
        effect: { _ in [:] },
        touches: { op, db in
            guard let noteId = op["id"] as? String,
                let path = try Notes.pathOf(db, nid: noteId)
            else {
                return []
            }
            
            return [path]
        }
    )
    
    public static let rebaseSource = OpHandler(
        schema: OpSchema(
            summary: "assert the note was verified against its current source files (no file edit): re-baseline the source fingerprint and clear source_stale",
            fields: [
                .required("id", role: .noteId, "target note id; must have a drift-tracked source"),
                .required("reason", "how the sources were verified/reconciled (recorded in note_lifecycle_events)")
            ],
            example: ##"{"op":"rebase_source","id":"my-note","reason":"note updated to reflect the reworked source file"}"##
        ),
        validate: { op, context, db in
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, db: db) {
                return rejection
            }
            
            let tracked = try Int.fetchOne(
                db,
                sql: "SELECT 1 FROM note_source WHERE note_id = ?",
                arguments: [noteId]
            )
            
            if tracked == nil { return "note has no drift-tracked source: \(noteId)" }
            
            return nil
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let noteId = op["id"] as! String
            
            try NoteSources.rebase(
                db,
                noteId: noteId,
                paths: try NoteSources.noteSourcePaths(db, noteId: noteId),
                now: now
            )
            try Notes.recordLifecycleEvent(
                db,
                nid: noteId,
                kind: "source_rebased",
                reason: op["reason"] as? String,
                now: now
            )
            
            return ["status": "ok", "ids": [noteId], "note": "source re-baselined"]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let flag = OpHandler(
        schema: OpSchema(
            summary: "attach a maintenance flag to a note (no file edit). re-flagging same kind increments flag_count + bumps last_flagged_at + clears resolved_at.",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("kind", "one of: reconsolidate | stale_ref"),
                .required("reason", "human-readable rationale for the flag")
            ],
            example: ##"{"op":"flag","id":"my-note","kind":"reconsolidate","reason":"two near-duplicate notes detected"}"##
        ),
        validate: { op, context, db in
            let kind = op["kind"] as? String ?? ""
            
            if !Handlers.creatableFlagKinds.contains(kind) { return "invalid flag kind: \(kind)" }
            
            return try Handlers.checkIDKnown(op["id"] as? String ?? "", context: context, db: db)
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            
            try Ripple.addFlag(
                db,
                noteId: op["id"] as! String,
                kind: op["kind"] as! String,
                reason: op["reason"] as? String ?? "",
                now: now
            )
            
            return ["status": "ok", "ids": [op["id"]!], "note": "flagged \(op["kind"]!)"]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let resolveFlag = OpHandler(
        schema: OpSchema(
            summary: "mark a ripple_flag as resolved (sets resolved_at). idempotent — already-resolved flags are no-op.",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("kind", "flag kind to resolve (reconsolidate / stale_ref / enrich_review)"),
                .optional("reason", "what changed to resolve it (recorded in note_lifecycle_events)")
            ],
            example: ##"{"op":"resolve_flag","id":"my-note","kind":"reconsolidate","reason":"merged with sibling"}"##
        ),
        validate: { op, context, db in
            let kind = op["kind"] as? String ?? ""
            
            if !Handlers.resolvableFlagKinds.contains(kind) { return "invalid flag kind: \(kind)" }
            
            return try Handlers.checkIDKnown(op["id"] as? String ?? "", context: context, db: db)
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let resolved = try Ripple.resolve(
                db,
                noteId: op["id"] as! String,
                kind: op["kind"] as! String,
                reason: op["reason"] as? String,
                now: now
            )
            
            return [
                "status": "ok",
                "ids": [op["id"]!],
                "note": resolved > 0
                    ? "resolved \(op["kind"]!)"
                    : "no unresolved flag of kind \(op["kind"]!)"
            ]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let dismissCandidate = OpHandler(
        schema: OpSchema(
            summary: "record a *keep* decision for a consolidation candidate — \"reviewed, leave this note as-is\". "
            + "Habituation: the candidate stops re-surfacing until the note's shape diverges past an accumulating "
            + "threshold (each dismissal deepens it) or a corpus-wide reorg reopens it. No file edit; affects only "
            + "the candidate channel, never retrieval.",
            fields: [
                .required("id", unless: "target", role: .noteId, "target note id (note-scope findings)"),
                .optional("target", "for a corpus-scope lint warn (`query lint` printed scope=corpus): the "
                    + "`subject` it reported, e.g. `tag-pair:금리|금융`. Mutually exclusive with `id` — "
                    + "a corpus fact belongs to no note, so it is not addressable by one."),
                .required("kind", "`split`, or `lint:<code>` for a lint warn you reviewed and are keeping "
                    + "(e.g. lint:dangling-note-ref). Errors are not dismissible."),
                .optional("finding", "for a lint kind: the finding you reviewed — the message, or any "
                    + "substring that picks it out. Required when the target carries more than one "
                    + "finding of that code, so a keep-decision answers one judgment instead of "
                    + "silencing the whole code on that target."),
                .optional("reason", "why it's being kept (recorded for audit + shown if it re-surfaces)")
            ],
            example: ##"{"op":"dismiss_candidate","id":"my-note","kind":"split","reason":"한 응집 주제 — 크기는 분할 사유 아님"}"##
        ),
        validate: { op, context, db in
            let kind = op["kind"] as? String ?? ""
            let hasId = !((op["id"] as? String) ?? "").isEmpty
            let hasTarget = !((op["target"] as? String) ?? "").isEmpty
            
            if hasId && hasTarget {
                return "pass `id` (note-scope) or `target` (corpus-scope), not both — a finding has one target"
            }
            
            if let code = Dismissals.lintCode(of: kind) {
                if !LintRules.dismissibleCodes.contains(code) {
                    let known = LintRules.dismissibleCodes.sorted().joined(separator: ", ")
                    
                    return LintRules.errorCodes.contains(code)
                        ? "lint code '\(code)' is an error, not a warn — invariant violations are not dismissible; fix it"
                        : "unknown dismissible lint code: \(code) (warns: \(known))"
                }
                
                let target: LintTarget = hasTarget
                    ? .corpus(op["target"] as! String)
                    : .note((op["id"] as? String) ?? "")
                let allFindings = try Lint.lintAll(db).filter { issue in issue.code == code }
                let liveFindings = allFindings.filter { issue in issue.target == target }
                
                if liveFindings.isEmpty {
                    let subjects = Set(
                        allFindings.map { issue in "\(issue.target.scope):\(issue.target.subject)" }
                    ).sorted()
                    let shown = subjects.prefix(5).joined(separator: ", ")
                    let more = subjects.count > 5 ? " +\(subjects.count - 5) more" : ""
                    
                    return "no live '\(code)' finding on \(target.scope) '\(target.subject)' — nothing to dismiss"
                        + (shown.isEmpty ? "" : " (live subjects: \(shown)\(more))")
                }
                
                let selector = (op["finding"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let selector, !selector.isEmpty {
                    let hits = liveFindings.filter { issue in issue.message.contains(selector) }
                    
                    if hits.isEmpty {
                        return "no '\(code)' finding on \(target.subject) contains \"\(selector.prefix(60))\" — "
                            + "dismiss the finding you actually reviewed"
                    }
                    
                    if hits.count > 1 {
                        return "that `finding` selector is ambiguous — \(hits.count) '\(code)' findings on "
                            + "\(target.subject) match; give a longer substring"
                    }
                } else if liveFindings.count > 1 {
                    return "\(target.subject) has \(liveFindings.count) '\(code)' findings — pass `finding` to say which "
                        + "one you reviewed; dismissing the code outright would bury the others "
                        + "(and any added later)"
                }
                
                if hasTarget { return nil }
            } else if !Dismissals.dismissibleKinds.contains(kind) {
                return "invalid candidate kind: \(kind) (dismissible: "
                    + "\(Dismissals.dismissibleKinds.sorted().joined(separator: " | ")) | lint:<warn-code>)"
            } else if hasTarget {
                return "`target` is for corpus-scope lint warns only — '\(kind)' is a note candidate, use `id`"
            }
            
            return try Handlers.checkIDKnown(op["id"] as? String ?? "", context: context, db: db)
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let target: LintTarget = ((op["target"] as? String)
                .map { value in value.isEmpty ? nil : value } ?? nil)
                .map { subject in LintTarget.corpus(subject) } ?? .note(op["id"] as! String)
            var kind = op["kind"] as! String
            
            if let code = Dismissals.lintCode(of: kind),
                Dismissals.lintFingerprint(of: kind) == nil {
                let liveFindings = try Lint.lintAll(db).filter { issue in
                    issue.code == code && issue.target == target
                }
                let selector = (op["finding"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let matched = (selector?.isEmpty == false)
                    ? liveFindings.first { issue in issue.message.contains(selector!) }
                    : (liveFindings.count == 1 ? liveFindings.first : nil)
                
                guard let matched else {
                    throw NSError(domain: "Handlers", code: 1, userInfo: [
                        NSLocalizedDescriptionKey:
                            "dismiss_candidate: '\(code)' finding on \(target.subject) is no longer present at write "
                            + "time — another op in this batch changed the note; dismiss it in a separate call"
                    ])
                }
                
                kind = Dismissals.lintKind(code, fingerprint: matched.dismissalKey)
            }
            
            try Dismissals.record(
                db,
                target: target,
                kind: kind,
                reason: op["reason"] as? String,
                now: now
            )
            
            let ids: [String] = {
                if case .note(let noteId) = target { return [noteId] }
                
                return []
            }()
            
            return [
                "status": "ok",
                "ids": ids,
                "note": "dismissed \(kind) candidate on \(target.scope) '\(target.subject)'"
            ]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let markUsed = OpHandler(
        schema: OpSchema(
            summary: "mark recently surfaced notes as used in the caller's response — a *weak* usage "
            + "signal, never a proof of causal use. With `response` text each note must pass a "
            + "content-overlap heuristic and is recorded as `content_overlap`; without it the mark "
            + "is recorded as caller-`reported`. Notes not surfaced in a recent activity window are "
            + "rejected: usage of an unobserved note is not an observation.",
            fields: [
                .required("ids", role: .noteIdList, "note ids the response actually drew on (array)"),
                .optional("response", "the final response text — enables the content-overlap check; "
                    + "omit to record a bare caller report")
            ],
            example: ##"{"op":"mark_used","ids":["transfer-flow","apigw-routing"],"response":"...최종 응답 본문..."}"##
        ),
        validate: { op, _, db in
            guard let raw = op["ids"] as? [Any], !raw.isEmpty else {
                return "ids must be a non-empty array of note ids"
            }
            
            let ids = raw.compactMap { value in value as? String }
            
            if ids.count != raw.count { return "ids must all be strings" }
            
            let now = Int(Date().timeIntervalSince1970)
            let cutoff = now - Activation.usedLookbackSec
            let label = Env.retrievalSession(cli: nil)
            
            func surfacedCount(_ id: String) throws -> Int {
                if let label, !label.isEmpty {
                    return try Int.fetchOne(db, sql: """
                        SELECT COUNT(*) FROM retrieval_hits h
                        JOIN activity_windows w ON w.id = h.window_id
                        WHERE h.note_id = ? AND h.surfaced_at >= ? AND w.label = ?
                        """, arguments: [id, cutoff, label]) ?? 0
                }
                
                return try Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM retrieval_hits WHERE note_id = ? AND surfaced_at >= ?
                    """, arguments: [id, cutoff]) ?? 0
            }
            
            for id in ids {
                if try surfacedCount(id) == 0 {
                    _ = try? Activation.deriveWindows(db, now: now)
                    
                    if try surfacedCount(id) == 0 {
                        return "note '\(id)' was not surfaced in any recent activity window"
                            + ((label?.isEmpty == false) ? " of session '\(label!)'" : "")
                            + " (lookback \(Activation.usedLookbackSec)s) — cannot mark unobserved usage"
                    }
                }
            }
            
            return nil
        },
        write: { op, db in
            let ids = (op["ids"] as! [Any]).compactMap { value in value as? String }
            let now = Int(Date().timeIntervalSince1970)
            let outcomes = try Activation.markUsed(
                db,
                ids: ids,
                response: op["response"] as? String,
                sessionLabel: Env.retrievalSession(cli: nil),
                now: now
            )
            let marked = outcomes.filter { outcome in outcome.matched }
            let failed = outcomes.filter { outcome in !outcome.matched }
            var note = "marked \(marked.count) note(s) used"
            
            if let first = marked.first { note += " (signal: \(first.signal))" }
            
            if !failed.isEmpty {
                let names = failed.map { outcome in outcome.noteId }.joined(separator: ", ")
                note += "; overlap check failed for: \(names)"
            }
            
            return ["status": "ok", "ids": marked.map { outcome in outcome.noteId }, "note": note]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let setGene = OpHandler(
        schema: OpSchema(
            summary: "set a gene's per-brain value directly. Works on every cataloged gene (locked "
            + "write-path genes included; the lock only bars the homeostasis loop). Bounds-checked; "
            + "recorded in genome_events with provenance. Pass value=null to reset to wild-type.",
            fields: [
                .required("gene", "gene id from `genome list`"),
                .optional("value", "new numeric value within the gene's bounds; null/absent resets to wild-type"),
                .optional("reason", "why — recorded as event detail")
            ],
            example: ##"{"op":"set_gene","gene":"links.sibling_rank_weight","value":0.2,"reason":"형제 도배 실측 완화"}"##
        ),
        validate: { op, _, _ in
            let id = op["gene"] as? String ?? ""
            
            guard let definition = Genome.gene(id) else {
                return "unknown gene: '\(id)' — see `genome list` for the catalog"
            }
            
            if let raw = op["value"], !(raw is NSNull) {
                guard let value = Handlers.asDouble(raw) else { return "value must be numeric" }
                
                if value < definition.min || value > definition.max {
                    return "value \(value) is outside gene '\(id)' bounds [\(definition.min), \(definition.max)]"
                }
            }
            
            return nil
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            let id = op["gene"] as! String
            let reason = op["reason"] as? String
            
            if let raw = op["value"], !(raw is NSNull), let value = Handlers.asDouble(raw) {
                let result = try GenomeService.setGene(
                    GRDBScope(db),
                    id: id,
                    value: value,
                    cause: "set_gene",
                    detail: reason,
                    requireMutable: false,
                    now: now
                )
                
                return [
                    "status": "ok",
                    "ids": [id],
                    "note": "gene \(id): \(result.old) → \(result.new)"
                ]
            }
            
            let old = try GenomeService.resetGene(GRDBScope(db), id: id, cause: "set_gene", now: now)
            
            return ["status": "ok", "ids": [id], "note": "gene \(id): \(old) → wild-type"]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let setNoteMeta = OpHandler(
        schema: OpSchema(
            summary: "upsert a (namespace, key, value) row in note_meta side-table",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("namespace", "lowercase + [a-z0-9_-]; plugin/feature owner namespace"),
                .required("key", "non-empty key within namespace"),
                .required("value", "string value (caller encodes JSON if needed)")
            ],
            example: ##"{"op":"set_note_meta","id":"my-note","namespace":"capture","key":"source_thread","value":"slack://..."}"##
        ),
        validate: { op, context, db in
            let namespace = op["namespace"] as? String ?? ""
            let nsNamespace = namespace as NSString
            
            if Handlers.namespaceRegex.firstMatch(
                in: namespace,
                range: NSRange(location: 0, length: nsNamespace.length)
            ) == nil {
                return "invalid namespace: '\(namespace)' (lowercase + [a-z0-9_-])"
            }
            
            guard let key = op["key"] as? String,
                !key.trimmingCharacters(in: .whitespaces).isEmpty
            else {
                return "key must be non-empty string"
            }
            
            guard op["value"] is String else {
                return "value must be string (plugin encodes JSON if needed)"
            }
            
            return try Handlers.checkIDKnown(op["id"] as? String ?? "", context: context, db: db)
        },
        write: { op, db in
            let now = Int(Date().timeIntervalSince1970)
            
            try UpsertNoteMetaTransaction(
                noteId: op["id"] as! String,
                namespace: op["namespace"] as! String,
                key: op["key"] as! String,
                value: op["value"] as! String,
                now: now
            )
                .perform(db)
            
            return [
                "status": "ok",
                "ids": [op["id"]!],
                "note": "meta \(op["namespace"]!)/\(op["key"]!) set"
            ]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    public static let deleteNoteMeta = OpHandler(
        schema: OpSchema(
            summary: "delete a (namespace, key) row from note_meta side-table",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("namespace", "lowercase + [a-z0-9_-]"),
                .required("key", "key within namespace")
            ],
            example: ##"{"op":"delete_note_meta","id":"my-note","namespace":"capture","key":"source_thread"}"##
        ),
        validate: { op, context, db in
            let namespace = op["namespace"] as? String ?? ""
            let nsNamespace = namespace as NSString
            
            if Handlers.namespaceRegex.firstMatch(
                in: namespace,
                range: NSRange(location: 0, length: nsNamespace.length)
            ) == nil {
                return "invalid namespace: '\(namespace)'"
            }
            
            return try Handlers.checkIDKnown(op["id"] as? String ?? "", context: context, db: db)
        },
        write: { op, db in
            let deleted = try DeleteNoteMetaTransaction(
                noteId: op["id"] as! String,
                namespace: op["namespace"] as! String,
                key: op["key"] as! String
            )
                .perform(db)
            
            return ["status": "ok", "ids": [op["id"]!], "note": "deleted \(deleted) meta row(s)"]
        },
        effect: { _ in [:] },
        touches: { _, _ in [] }
    )
    
    // MARK: - Initializer
    // MARK: - Public
    // MARK: - Private
}
