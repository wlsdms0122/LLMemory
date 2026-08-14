//
//  HandlersStructural.swift
//  LLMemory
//
//  Created by JSilver on 8/7/26.
//

import Foundation

public enum HandlersStructural {
    // MARK: - Property
    public static let restore = OperationHandler(
        schema: OperationSchema(
            summary: "restore a trashed note (cortex/.trash/) back to its address with a fresh DB row",
            fields: [
                .required("id", role: .noteId, "target note id; must exist in cortex/.trash/"),
                .optional("reason", "lifecycle event reason recorded on restore")
            ],
            example: ##"{"op":"restore","id":"deleted-note","reason":"deleted by mistake"}"##
        ),
        validate: { op, context, scope in
            let noteId = op["id"] as? String ?? ""
            let state = try Handlers.existingState(scope)
            
            if state.ids.contains(noteId) || context.inFlightIds.contains(noteId) {
                return "id collision: '\(noteId)' is already a live note — restoring would overwrite it"
            }
            
            do {
                if try Handlers.findTrashedFile(noteId) != nil { return nil }
            } catch {
                return "\(error)"
            }
            
            return "not in trash: \(noteId)"
        },
        write: { op, context, scope in
            let noteId = op["id"] as! String
            let now = context.now
            
            guard let found = try Handlers.findTrashedFile(noteId) else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "not in trash: \(noteId)"
                ])
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
            try (Frontmatter.dump(doc) + body).write(
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
        },
        effect: { op in ["creates": [op["id"] as? String ?? ""]] },
        touches: { op, _ in
            let noteId = op["id"] as? String ?? ""
            
            guard let found = try Handlers.findTrashedFile(noteId) else { return [] }
            
            return [found.url, Paths.file(forId: noteId)]
        }
    )
    
    public static let deleteNote = OperationHandler(
        schema: OperationSchema(
            summary: "soft-delete a note: file moves to cortex/.trash/, DB row removed; refuses if deliberate inbound links exist (reference/lineage — learned cooccur/assoc do not block)",
            fields: [
                .required("id", role: .noteId, "target note id"),
                .required("reason", "why deleting; recorded in trashed frontmatter (≤200 chars)"),
                .optional("force", "boolean; if true, bypasses the deliberate-inbound-link check")
            ],
            example: ##"{"op":"delete_note","id":"obsolete","reason":"merged into newer-note"}"##
        ),
        validate: { op, context, scope in
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, scope: scope) {
                return rejection
            }
            
            if (op["force"] as? Bool) == true { return nil }
            
            let inbound = try scope.run(FetchInboundBlockersTransaction(noteId: noteId))
            
            if !inbound.isEmpty {
                return "inbound links exist (src: \(inbound.joined(separator: ", "))) — resolve them or set force=true"
            }
            
            return nil
        },
        write: { op, context, scope in
            let noteId = op["id"] as! String
            let now = context.now
            
            guard let src = try scope.run(FetchNotePathTransaction(nid: noteId)) else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "unknown id: \(noteId)"
                ])
            }
            
            _ = try scope.run(FlagInboundReferrersTransaction(
                targetId: noteId,
                reason: "deleted \(noteId)",
                now: now
            ))
            
            let trashPath = try Trash.file(
                src,
                reason: op["reason"] as? String ?? "",
                now: now
            )
            
            try scope.run(DeleteNoteRowTransaction(nid: noteId))
            try scope.run(DeleteNoteEntitiesTransaction(noteId: noteId))
            try scope.run(DeleteNoteRippleFlagsTransaction(noteId: noteId))
            
            let reasonShort = (op["reason"] as? String ?? "").unicodeScalarPrefix(80)
            
            return [
                "status": "ok",
                "ids": [noteId],
                "path": (trashPath ?? src).path,
                "note": "deleted (backup at .trash/, reason: \(reasonShort))"
            ]
        },
        effect: { op in ["removes": [op["id"] as? String ?? ""]] },
        touches: { op, scope in
            guard let noteId = op["id"] as? String,
                let src = try scope.run(FetchNotePathTransaction(nid: noteId))
            else {
                return []
            }
            
            return Trash.destination(of: src).map { destination in [src, destination] } ?? [src]
        }
    )
    
    public static let migrateNote = OperationHandler(
        schema: OperationSchema(
            summary: "re-address a note — the file relocates to match the new id and every citation of the old id is rewritten",
            fields: [
                .required("id", role: .noteId, "current note id"),
                .required("new_id", role: .noteId, "new id — dot-joined labels; the file moves to match")
            ],
            example: ##"{"op":"migrate_note","id":"flow.my-note","new_id":"flow.review.my-note"}"##
        ),
        validate: { op, context, scope in
            let noteId = op["id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(noteId, context: context, scope: scope) {
                return rejection
            }
            
            let state = try Handlers.existingState(scope)
            let newId = (op["new_id"] as? String) ?? noteId
            let nsNewId = newId as NSString
            
            if Paths.idRegex.firstMatch(
                in: newId,
                range: NSRange(location: 0, length: nsNewId.length)
            ) == nil {
                return "invalid new_id format: \(newId)"
            }
            
            if newId != noteId && state.ids.contains(newId) { return "new_id collision: \(newId)" }
            
            return nil
        },
        write: { op, context, scope in
            let targetId = op["id"] as! String
            let newId = (op["new_id"] as? String) ?? targetId
            let newPath = Paths.file(forId: newId)
            
            guard let srcPath = try scope.run(FetchNotePathTransaction(nid: targetId)),
                FileManager.default.fileExists(atPath: srcPath.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "migrate source missing: \(targetId)"
                ])
            }
            
            let (doc, body) = try Frontmatter.parse(try String(contentsOf: srcPath, encoding: .utf8))
            
            try FileManager.default.createDirectory(
                at: newPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            let now = context.now
            
            try (Frontmatter.dump(doc) + body).write(to: newPath, atomically: true, encoding: .utf8)
            
            if newPath != srcPath {
                try FileManager.default.removeItem(at: srcPath)
            }
            
            let oldEntityHits: [(entity: String, hits: Int)] = (newId != targetId)
                ? try scope.run(FetchNoteEntityHitsTransaction(noteId: targetId))
                : []
            
            try scope.run(ReindexNoteFileTransaction(path: newPath))
            
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
                rewritten = try scope.run(RewriteInboundCitationsTransaction(
                    from: targetId,
                    to: newId
                ))
            }
            
            try scope.run(StampNoteLifecycleTransaction(nid: newId, now: now, isNew: false))
            
            let citations = rewritten.isEmpty
                ? ""
                : " (\(rewritten.count) citing note\(rewritten.count == 1 ? "" : "s") rewritten)"
            
            return [
                "status": "ok",
                "path": newPath.path,
                "ids": [newId] + rewritten,
                "note": "migrated \(targetId) -> \(newId)\(citations)"
            ]
        },
        effect: { op in
            let newId = (op["new_id"] as? String) ?? (op["id"] as? String ?? "")
            let id = op["id"] as? String ?? ""
            
            if newId != id {
                return ["creates": [newId], "removes": [id]]
            }
            
            return [:]
        },
        touches: { op, scope in
            var paths: [URL] = []
            
            if let noteId = op["id"] as? String, let src = try scope.run(FetchNotePathTransaction(nid: noteId)) {
                paths.append(src)
            }
            
            guard let targetId = op["id"] as? String else { return paths }
            
            paths.append(Paths.file(forId: (op["new_id"] as? String) ?? targetId))
            
            // The notes that cite this id are rewritten by the write, so they
            // belong in the snapshot — a rollback has to put them back.
            for src in try scope.run(FetchCitingNoteIdsTransaction(marker: targetId)) {
                paths.append(Paths.file(forId: src))
            }
            
            return paths
        }
    )
    
    public static let renameTag = OperationHandler(
        schema: OperationSchema(
            summary: "rename a tag across all notes",
            fields: [
                .required("from_tag", "current tag; must exist (in vocab or in use)"),
                .required("to_tag", "new tag (lowercase + [a-z0-9-])"),
                .optional("add_alias", "boolean; if true, persist from_tag → to_tag as a vocab alias")
            ],
            example: ##"{"op":"rename_tag","from_tag":"oldtag","to_tag":"newtag","add_alias":true}"##
        ),
        validate: { op, _, scope in
            let fromTag = op["from_tag"] as! String
            let toTag = op["to_tag"] as! String
            
            if fromTag == toTag { return "from_tag equals to_tag" }
            
            let nsToTag = toTag as NSString
            
            if Handlers.tagRegex.firstMatch(
                in: toTag,
                range: NSRange(location: 0, length: nsToTag.length)
            ) == nil {
                return "invalid to_tag format: \(toTag)"
            }
            
            let exists = try scope.run(TagVocabExistsTransaction(tag: fromTag))
                || (try scope.run(TagInUseTransaction(tag: fromTag)))
            
            if !exists { return "unknown from_tag: \(fromTag)" }
            
            let canonical = try scope.run(CanonicalizeTagTransaction(tag: toTag))
            
            if canonical != toTag && canonical != fromTag {
                return "to_tag '\(toTag)' is an alias of '\(canonical)' — rename to '\(canonical)' or drop the alias first"
            }
            
            return nil
        },
        write: { op, context, scope in
            let fromTag = op["from_tag"] as! String
            let toTag = op["to_tag"] as! String
            let addAlias = (op["add_alias"] as? Bool) ?? false
            let now = context.now
            let affectedIds = try scope.run(FetchNotesWithTagTransaction(tag: fromTag))
            
            for noteId in affectedIds {
                guard let path = try scope.run(FetchNotePathTransaction(nid: noteId)),
                    FileManager.default.fileExists(atPath: path.path)
                else {
                    throw NSError(domain: "Handlers", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "note file missing during rename_tag: \(noteId)"
                    ])
                }
                
                var (doc, body) = try Frontmatter.parse(
                    try String(contentsOf: path, encoding: .utf8)
                )
                var newTags: [String] = []
                var replaced = false
                
                for tag in doc.tags {
                    if tag == fromTag && !replaced {
                        newTags.append(toTag)
                        replaced = true
                    } else if tag == toTag {
                        continue
                    } else {
                        newTags.append(tag)
                    }
                }
                
                doc.tags = newTags
                
                try (Frontmatter.dump(doc) + body).write(
                    to: path,
                    atomically: true,
                    encoding: .utf8
                )
            }
            
            try scope.run(EnsureTagTransaction(tag: toTag, now: now))
            try scope.run(DropTagAliasClaimTransaction(alias: toTag))

            // The rewritten files are the truth now — reproject each note so
            // tags, content_hash and FTS follow the rename, same as every
            // other file-rewriting handler. Retirement must come after: the
            // vocab delete is FK-blocked until reprojection clears the old
            // tag's rows.
            for noteId in affectedIds {
                guard let path = try scope.run(FetchNotePathTransaction(nid: noteId)) else { continue }

                try scope.run(ReindexNoteFileTransaction(path: path))
            }

            if addAlias {
                try scope.run(AddTagAliasTransaction(alias: fromTag, canonical: toTag, now: now))
            }

            try scope.run(RetireTagTransaction(tag: fromTag, successor: toTag))
            
            let note = "renamed tag \(fromTag) -> \(toTag) (\(affectedIds.count) notes)"
                + (addAlias ? " + alias" : "")
            
            return ["status": "ok", "ids": affectedIds, "note": note]
        },
        effect: { _ in [:] },
        touches: { op, scope in
            let ids = try scope.run(FetchNotesWithTagTransaction(tag: op["from_tag"] as! String))
            
            return try ids.compactMap { noteId in try scope.run(FetchNotePathTransaction(nid: noteId)) }
        }
    )
    
    public static let relocateSection = OperationHandler(
        schema: OperationSchema(
            summary: "move a section from one note to another (extract from src + insert into dst)",
            fields: [
                .required("from_id", role: .noteId, "source note id"),
                .required("to_id", role: .noteId, "destination note id (must differ from from_id)"),
                .required("section", ###"section path with heading marker, e.g. "## 제목""###),
                .optional("position", ###"insertion target in dst: "end" (default) | "start" | {"after": "## path"} | {"before": "## path"}"###)
            ],
            example: ###"{"op":"relocate_section","from_id":"src-note","to_id":"dst-note","section":"## 부록","position":"end"}"###
        ),
        validate: { op, context, scope in
            let fromId = op["from_id"] as? String ?? ""
            let toId = op["to_id"] as? String ?? ""
            
            if fromId == toId { return "from_id and to_id must differ" }
            
            if let rejection = try Handlers.checkIDKnown(fromId, context: context, scope: scope) {
                return rejection
            }
            
            if let rejection = try Handlers.checkIDKnown(toId, context: context, scope: scope) {
                return rejection
            }
            
            do {
                _ = try SectionEdit.parsePath(op["section"] as? String ?? "")
            } catch {
                return "invalid section path: \(error)"
            }
            
            let position = op["position"] ?? "end"
            
            if let anchor = position as? String, anchor == "end" || anchor == "start" {
                return nil
            }
            
            if let anchor = position as? [String: Any] {
                if anchor["after"] != nil || anchor["before"] != nil { return nil }
                
                return "position dict requires after or before"
            }
            
            return "position must be 'end'/'start' or {after|before: <path>}"
        },
        write: { op, context, scope in
            let fromId = op["from_id"] as! String
            let toId = op["to_id"] as! String
            
            guard let srcPath = try scope.run(FetchNotePathTransaction(nid: fromId)),
                FileManager.default.fileExists(atPath: srcPath.path),
                let dstPath = try scope.run(FetchNotePathTransaction(nid: toId)),
                FileManager.default.fileExists(atPath: dstPath.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "note missing"
                ])
            }
            
            let (srcDoc, srcBody) = try Frontmatter.parse(
                try String(contentsOf: srcPath, encoding: .utf8)
            )
            let (dstDoc, dstBody) = try Frontmatter.parse(
                try String(contentsOf: dstPath, encoding: .utf8)
            )
            let sectionPath = try SectionEdit.parsePath(op["section"] as! String)
            let (extracted, srcRemaining) = try SectionEdit.extract(srcBody, paths: [sectionPath])
            let position = op["position"] ?? "end"
            let newDst: String
            
            if let anchor = position as? String, anchor == "end" {
                newDst = try SectionEdit.insert(
                    dstBody,
                    newSectionText: extracted,
                    anchor: .atEnd
                )
            } else if let anchor = position as? String, anchor == "start" {
                newDst = extracted + (extracted.hasSuffix("\n") ? "" : "\n") + dstBody
            } else if let anchor = position as? [String: Any],
                let after = anchor["after"] as? String {
                newDst = try SectionEdit.insert(
                    dstBody,
                    newSectionText: extracted,
                    anchor: .after(try SectionEdit.parsePath(after))
                )
            } else if let anchor = position as? [String: Any],
                let before = anchor["before"] as? String {
                newDst = try SectionEdit.insert(
                    dstBody,
                    newSectionText: extracted,
                    anchor: .before(try SectionEdit.parsePath(before))
                )
            } else {
                throw NSError(domain: "Handlers", code: 2)
            }
            
            try (Frontmatter.dump(srcDoc) + srcRemaining).write(
                to: srcPath,
                atomically: true,
                encoding: .utf8
            )
            try (Frontmatter.dump(dstDoc) + newDst).write(
                to: dstPath,
                atomically: true,
                encoding: .utf8
            )
            try scope.run(ReindexNoteFileTransaction(path: srcPath))
            try scope.run(ReindexNoteFileTransaction(path: dstPath))
            
            let now = context.now
            
            try scope.run(StampNoteLifecycleTransaction(nid: fromId, now: now, isNew: false))
            try scope.run(StampNoteLifecycleTransaction(nid: toId, now: now, isNew: false))
            try Handlers.recordEdit(
                scope,
                nid: fromId,
                opLabel: "relocate_section/from→\(toId)",
                now: now
            )
            try Handlers.recordEdit(
                scope,
                nid: toId,
                opLabel: "relocate_section/from←\(fromId)",
                now: now
            )
            
            return [
                "status": "ok",
                "paths": [srcPath.path, dstPath.path],
                "ids": [fromId, toId],
                "note": "relocated section to \(toId)"
            ]
        },
        effect: { _ in [:] },
        touches: { op, scope in
            var paths: [URL] = []
            
            if let fromId = op["from_id"] as? String,
                let path = try scope.run(FetchNotePathTransaction(nid: fromId)) {
                paths.append(path)
            }
            
            if let toId = op["to_id"] as? String, let path = try scope.run(FetchNotePathTransaction(nid: toId)) {
                paths.append(path)
            }
            
            return paths
        }
    )
    
    public static let splitNote = OperationHandler(
        schema: OperationSchema(
            summary: "split a note into ≥2 children by section paths; routes the source's links/aliases/meta across new ids",
            fields: [
                .required("from_id", role: .noteId, "source note id"),
                .required("into", role: .childSpecs, "list (≥2) of child specs: each requires {id, title, tags, summary, sections}; optional {priority, source, content_prefix}"),
                .optional("remainder", ##"{"keep": bool} — if true and remainder is non-empty, keep src note with leftover sections; default false (delete src)"##),
                .optional("routing", ##"list resolving a split conflict — each {type:"link"|"term", <identity>, to:[child ids]}. identity: link→{kind,neighbor}, term→{term}. to=["a"] assign, ["a","b"] copy, []=drop; omitted artifacts drop. cooccur/reference are auto-handled. A source-deleting split with unrouted assoc/lineage links or active aliases returns a `conflict` listing them."##)
            ],
            example: ###"{"op":"split_note","from_id":"persona.big-note","into":[{"id":"persona.big-note.a","title":"A","tags":["persona"],"summary":"...","sections":["## A"]},{"id":"persona.big-note.b","title":"B","tags":["persona"],"summary":"...","sections":["## B"]}]}"###
        ),
        validate: { op, context, scope in
            let fromId = op["from_id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(fromId, context: context, scope: scope) {
                return rejection
            }
            
            guard let into = op["into"] as? [[String: Any]], into.count >= 2 else {
                return "into must be a list of at least 2 child specs"
            }
            
            var newIds = Set<String>()
            let state = try Handlers.existingState(scope)
            var normalized: [[String: Any]] = into
            var allPaths: [SectionEdit.SectionPath] = []
            
            for index in 0..<into.count {
                let child = into[index]
                
                for field in ["id", "title", "tags", "summary", "sections"] {
                    if child[field] == nil {
                        return "into[\(index)] missing/empty field: \(field)"
                    }
                    
                    if let value = child[field] as? String, value.isEmpty {
                        return "into[\(index)] missing/empty field: \(field)"
                    }
                }
                
                let childId = child["id"] as! String
                let nsChildId = childId as NSString
                
                if Paths.idRegex.firstMatch(
                    in: childId,
                    range: NSRange(location: 0, length: nsChildId.length)
                ) == nil {
                    return "into[\(index)] invalid id: \(childId)"
                }
                
                if (state.ids.contains(childId) || context.inFlightIds.contains(childId))
                    && childId != fromId {
                    return "into[\(index)] id collision: \(childId)"
                }
                
                if newIds.contains(childId) { return "into[\(index)] duplicate id: \(childId)" }
                
                newIds.insert(childId)
                
                guard let tags = child["tags"] as? [Any], !tags.isEmpty else {
                    return "into[\(index)] tags must be non-empty list"
                }
                
                guard let sections = child["sections"] as? [Any], !sections.isEmpty else {
                    return "into[\(index)] sections must be non-empty list"
                }
                
                if let rejection = Handlers.sourceInputError(child["source"]) {
                    return "into[\(index)] \(rejection)"
                }
                
                var normalizedSections: [String] = []
                
                for rawSection in sections {
                    var section = (rawSection as? String ?? "")
                        .trimmingCharacters(in: .whitespaces)
                    
                    if !section.isEmpty && !section.hasPrefix("#") {
                        section = "## \(section)"
                    }
                    
                    let parsed: SectionEdit.SectionPath
                    do {
                        parsed = try SectionEdit.parsePath(section)
                    } catch {
                        return "into[\(index)] invalid section path '\(section)': \(error)"
                    }
                    
                    allPaths.append(parsed)
                    normalizedSections.append(section)
                }
                
                normalized[index]["sections"] = normalizedSections
            }
            
            if let srcPath = try scope.run(FetchNotePathTransaction(nid: fromId)),
                let raw = try? String(contentsOf: srcPath, encoding: .utf8) {
                let (_, srcBody) = try Frontmatter.parse(raw)
                
                do {
                    _ = try SectionEdit.resolveDisjoint(srcBody, paths: allPaths)
                } catch {
                    return "into sections do not form a valid split of '\(fromId)': \(error)"
                }
            }
            
            let routing = parseRouting(op)
            
            for (_, targets) in routing {
                for target in targets where !newIds.contains(target) {
                    return "routing target '\(target)' is not one of the new children"
                }
            }
            
            let keepSrc = (op["remainder"] as? [String: Any])?["keep"] as? Bool ?? false
            
            if !keepSrc {
                let uncovered = try uncoveredRouteArtifacts(scope, fromId: fromId, routing: routing)
                
                if !uncovered.isEmpty {
                    throw SplitConflict(fromId: fromId, unresolved: uncovered)
                }
            }
            
            return nil
        },
        write: { op, context, scope in
            let fromId = op["from_id"] as! String
            
            guard let srcPath = try scope.run(FetchNotePathTransaction(nid: fromId)),
                FileManager.default.fileExists(atPath: srcPath.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "split source missing: \(fromId)"
                ])
            }
            
            let (srcDoc, srcBody) = try Frontmatter.parse(
                try String(contentsOf: srcPath, encoding: .utf8)
            )
            let (outboundEdges, inboundEdges) = try scope.run(FetchLinkFanTransaction(fromId: fromId))
            let routing = parseRouting(op)
            let srcTerms = try scope.run(FetchActiveTermRowsTransaction(noteId: fromId))
            var written: [URL] = []
            var newIds: [String] = []
            let now = context.now
            var remaining = srcBody
            let intoChildren = (op["into"] as? [[String: Any]]) ?? []
            
            for child in intoChildren {
                let rawSections = (child["sections"] as? [Any])?
                    .compactMap { section in section as? String } ?? []
                let normalizedSections = rawSections.map { section -> String in
                    let trimmed = section.trimmingCharacters(in: .whitespaces)
                    
                    return (trimmed.hasPrefix("#") || trimmed.isEmpty) ? trimmed : "## \(trimmed)"
                }
                let sectionPaths = try normalizedSections.map { section in
                    try SectionEdit.parsePath(section)
                }
                let (extracted, rest) = try SectionEdit.extract(remaining, paths: sectionPaths)
                remaining = rest
                
                let childId = child["id"] as! String
                let childPath = Paths.file(forId: childId)
                
                try FileManager.default.createDirectory(
                    at: childPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                
                var childDoc = FrontmatterDoc(
                    title: child["title"] as? String ?? "",
                    priority: child["priority"] as? String ?? "lazy",
                    summary: child["summary"] as? String ?? "",
                    tags: (child["tags"] as? [Any])?.compactMap { tag in tag as? String } ?? []
                )
                childDoc.source = child["source"] != nil
                    ? try Handlers.finalizeSource(child["source"])
                    : srcDoc.source
                
                let prefix = (child["content_prefix"] as? String).map { text in
                    String(
                        text.reversed().drop(while: { character in character.isWhitespace }).reversed()
                    ) + "\n\n"
                } ?? ""
                let content = prefix + extracted
                
                try (Frontmatter.dump(childDoc) + content).write(
                    to: childPath,
                    atomically: true,
                    encoding: .utf8
                )
                try scope.run(ReindexNoteFileTransaction(path: childPath))
                try scope.run(InheritSourceObservationTransaction(from: fromId, to: childId))
                try scope.run(StampNoteLifecycleTransaction(nid: childId, now: now, isNew: true))
                
                written.append(childPath)
                newIds.append(childId)
            }
            
            let keepRemainder = ((op["remainder"] as? [String: Any])?["keep"] as? Bool) ?? false
            let sourceSurvives = keepRemainder
                && !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            if keepRemainder && !sourceSurvives {
                let uncovered = try uncoveredRouteArtifacts(scope.readOnly, fromId: fromId, routing: routing)
                
                if !uncovered.isEmpty {
                    throw SplitConflict(fromId: fromId, unresolved: uncovered)
                }
            }
            
            if sourceSurvives {
                try (Frontmatter.dump(srcDoc) + remaining).write(
                    to: srcPath,
                    atomically: true,
                    encoding: .utf8
                )
                try scope.run(ReindexNoteFileTransaction(path: srcPath))
                try scope.run(StampNoteLifecycleTransaction(nid: fromId, now: now, isNew: false))
            } else {
                _ = try scope.run(FlagInboundReferrersTransaction(
                    targetId: fromId,
                    reason: "split into \(newIds.joined(separator: ", "))",
                    now: now
                ))
                try scope.run(DeleteNoteRowTransaction(nid: fromId))
                try Trash.file(
                    srcPath,
                    reason: "split into \(newIds.joined(separator: ", "))",
                    now: now
                )
            }
            
            let share = Double(max(1, newIds.count))
            
            func insertEdge(
                child: String,
                other: String,
                outbound: Bool,
                _ edge: LinkEdge,
                weight: Double
            ) throws {
                let src = outbound ? child : other
                let dst = outbound ? other : child
                
                try scope.run(AddLinkTransaction(
                    src: src,
                    dst: dst,
                    kind: edge.kind,
                    weight: weight,
                    createdAt: edge.createdAt,
                    lastActivatedAt: edge.lastActivatedAt,
                    provenance: edge.provenance
                ))
            }
            
            func redistribute(_ edges: [LinkEdge], outbound: Bool) throws {
                for edge in edges where edge.other != fromId {
                    switch NoteArtifacts.linkKindSplitPolicy[edge.kind] ?? .autoRedistribute {
                    case .rebuild, .drop:
                        continue
                    
                    case .route, .routeRevalidate:
                        if let targets = routing[routingKey(
                            type: "link",
                            kind: edge.kind,
                            neighbor: edge.other,
                            term: nil
                        )] {
                            for noteId in targets {
                                try insertEdge(
                                    child: noteId,
                                    other: edge.other,
                                    outbound: outbound,
                                    edge,
                                    weight: edge.weight
                                )
                            }
                        } else {
                            for noteId in newIds {
                                try insertEdge(
                                    child: noteId,
                                    other: edge.other,
                                    outbound: outbound,
                                    edge,
                                    weight: edge.weight / share
                                )
                            }
                        }
                    
                    case .autoRedistribute:
                        for noteId in newIds {
                            try insertEdge(
                                child: noteId,
                                other: edge.other,
                                outbound: outbound,
                                edge,
                                weight: edge.weight / share
                            )
                        }
                    
                    case .autoCopy:
                        for noteId in newIds {
                            try insertEdge(
                                child: noteId,
                                other: edge.other,
                                outbound: outbound,
                                edge,
                                weight: edge.weight
                            )
                        }
                    }
                }
            }
            
            try redistribute(outboundEdges, outbound: true)
            try redistribute(inboundEdges, outbound: false)
            
            for noteId in newIds { try scope.run(NormalizeUndirectedLinksTransaction(nodeId: noteId)) }
            
            try scope.run(LinkSiblingsTransaction(
                ids: sourceSurvives ? newIds + [fromId] : newIds,
                now: now
            ))
            
            if !sourceSurvives {
                for row in srcTerms {
                    let kind = row.kind
                    let term = row.term
                    let provenance = row.provenance
                    
                    guard let targets = routing[routingKey(
                        type: "term",
                        kind: nil,
                        neighbor: nil,
                        term: term
                    )] else {
                        continue
                    }
                    
                    for noteId in targets {
                        try scope.run(InsertPendingTermIfAbsentTransaction(
                            noteId: noteId,
                            kind: kind,
                            term: term,
                            provenance: provenance,
                            now: now
                        ))
                    }
                }
                
                try scope.run(DeleteNoteLinksTransaction(noteId: fromId))
            }
            
            return [
                "status": "ok",
                "paths": written.map { path in path.path },
                "ids": newIds,
                "note": "split \(fromId) -> \(newIds.count) children"
            ]
        },
        effect: { op in
            let into = (op["into"] as? [[String: Any]]) ?? []
            let newIds = into.compactMap { child in child["id"] as? String }
            let keep = ((op["remainder"] as? [String: Any])?["keep"] as? Bool) ?? false
            let fromId = op["from_id"] as? String ?? ""
            var effects: [String: [String]] = ["creates": newIds]
            
            if !keep && !newIds.contains(fromId) {
                effects["removes"] = [fromId]
            }
            
            return effects
        },
        touches: { op, scope in
            var paths: [URL] = []
            
            if let fromId = op["from_id"] as? String, let src = try scope.run(FetchNotePathTransaction(nid: fromId)) {
                paths.append(src)
                
                if let trashPath = Trash.destination(of: src) { paths.append(trashPath) }
            }
            
            for child in (op["into"] as? [[String: Any]]) ?? [] {
                if let childId = child["id"] as? String {
                    paths.append(Paths.file(forId: childId))
                }
            }
            
            return paths
        }
    )
    
    public static let mergeNotes = OperationHandler(
        schema: OperationSchema(
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
        ),
        validate: { op, context, scope in
            let intoId = op["into_id"] as? String ?? ""
            
            if let rejection = try Handlers.checkIDKnown(intoId, context: context, scope: scope) {
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
                if let rejection = try Handlers.checkIDKnown(fromId, context: context, scope: scope) {
                    return "from_ids: \(rejection)"
                }
            }
            
            guard let tags = op["tags"] as? [Any], !tags.isEmpty else {
                return "tags must be non-empty list"
            }
            
            if let rejection = Handlers.sourceInputError(op["source"]) { return rejection }
            
            return nil
        },
        write: { op, context, scope in
            let intoId = op["into_id"] as! String
            let fromIds = (op["from_ids"] as? [Any])?.compactMap { id in id as? String } ?? []
            
            guard let intoPath = try scope.run(FetchNotePathTransaction(nid: intoId)),
                FileManager.default.fileExists(atPath: intoPath.path)
            else {
                throw NSError(domain: "Handlers", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "merge target missing: \(intoId)"
                ])
            }
            
            var (intoDoc, _) = try Frontmatter.parse(
                try String(contentsOf: intoPath, encoding: .utf8)
            )
            intoDoc.title = (op["title"] as? String)
                ?? (intoDoc.title.isEmpty ? intoId : intoDoc.title)
            intoDoc.tags = (op["tags"] as? [Any])?.compactMap { tag in tag as? String }
                ?? intoDoc.tags
            intoDoc.summary = (op["summary"] as? String) ?? intoDoc.summary
            
            if let priority = op["priority"] as? String { intoDoc.priority = priority }
            
            if op["source"] != nil {
                intoDoc.source = try Handlers.finalizeSource(op["source"])
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
            
            try (Frontmatter.dump(intoDoc) + body).write(
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
                try Trash.file(path, reason: "merged into \(intoId)", now: now)
            }
            
            return [
                "status": "ok",
                "path": intoPath.path,
                "ids": [intoId],
                "note": "merged \(fromIds.count) into \(intoId)"
            ]
        },
        effect: { op in
            let fromIds = (op["from_ids"] as? [Any])?.compactMap { id in id as? String } ?? []
            
            return ["removes": fromIds]
        },
        touches: { op, scope in
            var paths: [URL] = []
            
            if let intoId = op["into_id"] as? String, let path = try scope.run(FetchNotePathTransaction(nid: intoId)) {
                paths.append(path)
            }
            
            let fromIds = (op["from_ids"] as? [Any])?.compactMap { id in id as? String } ?? []
            
            for fromId in fromIds {
                if let path = try scope.run(FetchNotePathTransaction(nid: fromId)) {
                    paths.append(path)
                    
                    if let trashPath = Trash.destination(of: path) { paths.append(trashPath) }
                }
            }
            
            return paths
        }
    )
    
    // MARK: - Initializer
    // MARK: - Public
    static func routingKey(
        type: String,
        kind: String?,
        neighbor: String?,
        term: String?
    ) -> String {
        switch type {
        case "link":
            return "link\u{1}\(kind ?? "")\u{1}\(neighbor ?? "")"
        
        case "term":
            return "term\u{1}\(term ?? "")"
        
        default:
            return "?\u{1}\(type)"
        }
    }
    
    static func routeArtifactKey(_ artifact: RouteArtifact) -> String {
        routingKey(
            type: artifact.type,
            kind: artifact.kind,
            neighbor: artifact.neighbor,
            term: artifact.term
        )
    }
    
    static func parseRouting(_ op: [String: Any]) -> [String: [String]] {
        var map: [String: [String]] = [:]
        
        for entry in (op["routing"] as? [[String: Any]]) ?? [] {
            let type = entry["type"] as? String ?? ""
            let targets = (entry["to"] as? [Any])?.compactMap { target in target as? String } ?? []
            
            map[routingKey(
                type: type,
                kind: entry["kind"] as? String,
                neighbor: entry["neighbor"] as? String,
                term: entry["term"] as? String
            )] = targets
        }
        
        return map
    }
    
    static func uncoveredRouteArtifacts(
        _ scope: GRDBReadScope,
        fromId: String,
        routing: [String: [String]]
    ) throws -> [RouteArtifact] {
        try scope.run(FetchSplitRouteTargetsTransaction(noteId: fromId)).filter { artifact in
            routing[routeArtifactKey(artifact)] == nil
        }
    }
    
    // MARK: - Private
}

public enum HandlersRegistry {
    // The registry is assembled per engine, so handlers that need a
    // collaborator capture it here — nothing reaches through the context.
    public static func build(genome: GenomeService) -> [String: OperationHandler] {
        [
            "create_note": HandlersBasic.createNote,
            "patch_section": HandlersBasic.patchSection,
            "set_frontmatter": HandlersBasic.setFrontmatter,
            "rename_section": HandlersBasic.renameSection,
            "flag": HandlersBasic.flag,
            "resolve_flag": HandlersBasic.resolveFlag,
            "dismiss_candidate": HandlersBasic.dismissCandidate,
            "mark_used": HandlersBasic.markUsed,
            "set_gene": HandlersBasic.setGene(genome: genome),
            "invalidate": HandlersBasic.invalidate,
            "revalidate": HandlersBasic.revalidate,
            "rebase_source": HandlersBasic.rebaseSource,
            "restore": HandlersStructural.restore,
            "delete_note": HandlersStructural.deleteNote,
            "migrate_note": HandlersStructural.migrateNote,
            "rename_tag": HandlersStructural.renameTag,
            "relocate_section": HandlersStructural.relocateSection,
            "split_note": HandlersStructural.splitNote,
            "merge_notes": HandlersStructural.mergeNotes,
            "add_retrieval_terms": HandlersEnrichment.addRetrievalTerms,
            "propose_link": HandlersEnrichment.proposeLink,
            "link_lineage": HandlersEnrichment.linkLineage,
            "purge_enrichment": HandlersEnrichment.purgeEnrichment
        ]
    }
}
