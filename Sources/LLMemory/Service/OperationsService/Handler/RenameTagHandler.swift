//
//  RenameTagHandler.swift
//  LLMemory
//
//  Created by JSilver on 8/15/26.
//

import Foundation

struct RenameTagHandler: OperationHandling {
    // MARK: - Property
    let schema = OperationSchema(
        summary: "rename a tag across all notes",
        fields: [
            .required("from_tag", "current tag; must exist (in vocab or in use)"),
            .required("to_tag", "new tag (lowercase + [a-z0-9-])"),
            .optional("add_alias", "boolean; if true, persist from_tag → to_tag as a vocab alias")
        ],
        example: ##"{"op":"rename_tag","from_tag":"oldtag","to_tag":"newtag","add_alias":true}"##
    )
    
    private let frontmatter = Frontmatter()
    
    // MARK: - Initializer
    // MARK: - Public
    func validate(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBReadScope
    ) throws -> String? {
        let fromTag = op["from_tag"] as! String
        let toTag = op["to_tag"] as! String
        
        if fromTag == toTag { return "from_tag equals to_tag" }
        
        let nsToTag = toTag as NSString
        
        if OpVocabulary.tagRegex.firstMatch(
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
    }
    
    func write(
        _ op: [String: Any],
        _ context: HandlerContext,
        _ scope: GRDBScope
    ) throws -> [String: Any] {
        let fromTag = op["from_tag"] as! String
        let toTag = op["to_tag"] as! String
        let addAlias = (op["add_alias"] as? Bool) ?? false
        let now = context.now
        let affectedIds = try scope.run(FetchNotesWithTagTransaction(tag: fromTag))
        
        for noteId in affectedIds {
            guard let path = try scope.run(FetchNotePathTransaction(nid: noteId)),
                FileManager.default.fileExists(atPath: path.path)
            else {
                throw OperationError.noteFileMissing("note file missing during rename_tag: \(noteId)")
            }
            
            var (doc, body) = try frontmatter.parse(
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
            
            try (frontmatter.dump(doc) + body).write(
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
    }
    
    func touches(_ op: [String: Any], _ scope: GRDBReadScope) throws -> [URL] {
        let ids = try scope.run(FetchNotesWithTagTransaction(tag: op["from_tag"] as! String))
        
        return try ids.compactMap { noteId in try scope.run(FetchNotePathTransaction(nid: noteId)) }
    }
    
    // MARK: - Private
}
